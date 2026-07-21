import type { NextFunction, Request, Response } from "express";
import { verifySession } from "../auth/session.js";

/** Require the single-user API bearer token on private API routes. */
export function requireToken(expected: string) {
  return (req: Request, res: Response, next: NextFunction): void => {
    const header = req.header("authorization") ?? "";
    const token = header.startsWith("Bearer ") ? header.slice(7) : "";

    if (!token || token !== expected) {
      res.status(401).json({ error: "unauthorized" });
      return;
    }

    next();
  };
}

export interface SessionAuthOptions {
  sessionSecret: string;
  apiToken: string;
  /**
   * User ID bound to the shared API token. Required for shared-token auth —
   * client-supplied userId is ignored so the token cannot access other accounts.
   */
  apiTokenUserId: string;
}

/**
 * Authenticate a /v1 request. Prefers a session JWT; falls back to the shared
 * API token which is permanently bound to `apiTokenUserId` (no client spoofing).
 */
export function requireSession(opts: SessionAuthOptions) {
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    const header = req.header("authorization") ?? "";
    const token = header.startsWith("Bearer ") ? header.slice(7) : "";
    if (!token) {
      res.status(401).json({ error: "unauthorized" });
      return;
    }

    const sessionUserId = await verifySession(token, opts.sessionSecret);
    if (sessionUserId) {
      req.userId = sessionUserId;
      next();
      return;
    }

    if (token === opts.apiToken) {
      if (!opts.apiTokenUserId) {
        res.status(401).json({ error: "api_token_user_unbound" });
        return;
      }
      // Ignore any client-supplied userId — the shared token maps to one user only.
      req.userId = opts.apiTokenUserId;
      next();
      return;
    }

    res.status(401).json({ error: "unauthorized" });
  };
}
