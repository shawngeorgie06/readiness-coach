import cors from "cors";
import express, { type NextFunction, type Request, type Response } from "express";
import helmet from "helmet";
import rateLimit from "express-rate-limit";
import { createAppleVerifier, type AppleVerifier } from "./auth/appleVerifier.js";
import { prisma } from "./db.js";
import { requireSession } from "./middleware/auth.js";
import { createAuthRouter } from "./routes/auth.js";
import { bodyRouter } from "./routes/body.js";
import { coachRouter } from "./routes/coach.js";
import { historyRouter } from "./routes/history.js";
import { sleepRouter } from "./routes/sleep.js";
import { syncRouter } from "./routes/sync.js";
import { todayRouter } from "./routes/today.js";
import { trainRouter } from "./routes/train.js";
import { userRouter } from "./routes/user.js";

export interface RateLimitOptions {
  windowMs: number;
  max: number;
}

export interface AppOptions {
  apiToken: string;
  /** User ID bound to apiToken — shared token cannot spoof other users. */
  apiTokenUserId: string;
  sessionSecret: string;
  appleBundleId?: string;
  appleVerifier?: AppleVerifier;
  checkDatabase?: () => Promise<unknown>;
  /** Origin allowed to make cross-origin requests. Unset = no cross-origin access. */
  corsOrigin?: string;
  rateLimit?: RateLimitOptions;
}

const defaultRateLimit: RateLimitOptions = { windowMs: 15 * 60 * 1000, max: 300 };

export function createApp({
  apiToken,
  apiTokenUserId,
  sessionSecret,
  appleBundleId,
  appleVerifier,
  checkDatabase = () => prisma.$queryRaw`SELECT 1`,
  corsOrigin,
  rateLimit: rateLimitOptions = defaultRateLimit,
}: AppOptions) {
  const app = express();
  // Render (and most hosts) terminate TLS at a proxy — needed for correct IPs.
  app.set("trust proxy", 1);
  app.use(helmet());
  app.use(
    cors({
      origin: corsOrigin
        ? (origin, callback) => callback(null, origin === corsOrigin)
        : false,
    }),
  );
  // Large bodies only for Health sync; keep a small default elsewhere (memory DoS).
  app.use((req, res, next) => {
    const limit = req.path === "/v1/sync" || req.path.startsWith("/v1/sync/") ? "50mb" : "256kb";
    express.json({ limit })(req, res, next);
  });

  app.get("/health", async (_req, res) => {
    try {
      await checkDatabase();
      res.json({ ok: true });
    } catch (error) {
      console.error("Database health check failed", error);
      res.status(503).json({ ok: false });
    }
  });

  app.use(
    "/v1",
    rateLimit({
      windowMs: rateLimitOptions.windowMs,
      limit: rateLimitOptions.max,
      standardHeaders: true,
      legacyHeaders: false,
    }),
  );

  const verifier = appleVerifier ?? (appleBundleId ? createAppleVerifier({ bundleId: appleBundleId }) : undefined);
  if (verifier) {
    app.use("/v1/auth", createAuthRouter({ verifier, sessionSecret, apiToken }));
  }

  app.use("/v1", requireSession({ sessionSecret, apiToken, apiTokenUserId }));
  app.use("/v1/sync", syncRouter);
  app.use("/v1/today", todayRouter);
  app.use("/v1/history", historyRouter);
  app.use("/v1/sleep", sleepRouter);
  app.use("/v1/train", trainRouter);
  app.use("/v1/body", bodyRouter);
  app.use("/v1/coach", coachRouter);
  app.use("/v1/user", userRouter);

  app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    if (res.headersSent) return;
    const status =
      typeof err === "object" && err != null && "status" in err && typeof (err as { status: unknown }).status === "number"
        ? (err as { status: number }).status
        : typeof err === "object" && err != null && "statusCode" in err && typeof (err as { statusCode: unknown }).statusCode === "number"
          ? (err as { statusCode: number }).statusCode
          : 500;
    if (status === 400 || status === 413) {
      res.status(status).json({ error: "bad_request" });
      return;
    }
    console.error(err);
    res.status(500).json({ error: "internal_error" });
  });

  return app;
}
