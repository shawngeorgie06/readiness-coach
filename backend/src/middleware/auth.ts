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

/**
 * Authenticate a /v1 request. Prefers a session JWT and falls back during
 * migration to the legacy shared token with an explicit user ID.
 */
export function requireSession(opts: { sessionSecret: string; apiToken: string }) {
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
      const queryUserId = typeof req.query.userId === "string" ? req.query.userId : "";
      const bodyUserId =
        req.body != null && typeof (req.body as Record<string, unknown>).userId === "string"
          ? (req.body as Record<string, unknown>).userId as string
          : "";
      req.userId = queryUserId || bodyUserId;
      next();
      return;
    }

    res.status(401).json({ error: "unauthorized" });
  };
}
