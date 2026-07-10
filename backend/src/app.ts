import cors from "cors";
import express from "express";
import { prisma } from "./db.js";
import { requireToken } from "./middleware/auth.js";
import { bodyRouter } from "./routes/body.js";
import { coachRouter } from "./routes/coach.js";
import { sleepRouter } from "./routes/sleep.js";
import { syncRouter } from "./routes/sync.js";
import { todayRouter } from "./routes/today.js";
import { trainRouter } from "./routes/train.js";

export interface AppOptions {
  apiToken: string;
  checkDatabase?: () => Promise<unknown>;
}

export function createApp({
  apiToken,
  checkDatabase = () => prisma.$queryRaw`SELECT 1`,
}: AppOptions) {
  const app = express();
  app.use(cors());
  app.use(express.json({ limit: "2mb" }));

  app.get("/health", async (_req, res) => {
    try {
      await checkDatabase();
      res.json({ ok: true });
    } catch (error) {
      console.error("Database health check failed", error);
      res.status(503).json({ ok: false });
    }
  });

  app.use("/v1", requireToken(apiToken));
  app.use("/v1/sync", syncRouter);
  app.use("/v1/today", todayRouter);
  app.use("/v1/sleep", sleepRouter);
  app.use("/v1/train", trainRouter);
  app.use("/v1/body", bodyRouter);
  app.use("/v1/coach", coachRouter);

  return app;
}
