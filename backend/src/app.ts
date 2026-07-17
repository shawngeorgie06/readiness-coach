import cors from "cors";
import express from "express";
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
  app.use(express.json({ limit: "50mb" }));

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

  app.use("/v1", requireSession({ sessionSecret, apiToken }));
  app.use("/v1/sync", syncRouter);
  app.use("/v1/today", todayRouter);
  app.use("/v1/history", historyRouter);
  app.use("/v1/sleep", sleepRouter);
  app.use("/v1/train", trainRouter);
  app.use("/v1/body", bodyRouter);
  app.use("/v1/coach", coachRouter);
  app.use("/v1/user", userRouter);

  return app;
}
