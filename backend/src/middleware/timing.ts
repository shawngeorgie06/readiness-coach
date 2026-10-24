import type { RequestHandler } from "express";

/**
 * Logs `METHOD /path STATUS Nms` once the response finishes. The path is taken
 * without its query string, so user IDs and other params never reach the log.
 */
export function createRequestTimer(
  log: (line: string) => void = console.log,
  now: () => number = () => performance.now(),
): RequestHandler {
  return (req, res, next) => {
    const start = now();
    res.on("finish", () => {
      const path = req.originalUrl.split("?")[0];
      log(`${req.method} ${path} ${res.statusCode} ${Math.round(now() - start)}ms`);
    });
    next();
  };
}
