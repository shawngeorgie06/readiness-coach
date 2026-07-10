import type { NextFunction, Request, Response } from "express";

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
