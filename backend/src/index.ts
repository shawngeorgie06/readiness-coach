import cors from "cors";
import express from "express";
import { loadEnv } from "./env.js";
import { requireToken } from "./middleware/auth.js";
import { bodyRouter } from "./routes/body.js";
import { coachRouter } from "./routes/coach.js";
import { sleepRouter } from "./routes/sleep.js";
import { syncRouter } from "./routes/sync.js";
import { todayRouter } from "./routes/today.js";
import { trainRouter } from "./routes/train.js";

const env = loadEnv();

const app = express();
app.use(cors());
app.use(express.json({ limit: "2mb" }));

app.get("/health", (_req, res) => {
  res.json({ ok: true });
});

app.use("/v1", requireToken(env.API_TOKEN));
app.use("/v1/sync", syncRouter);
app.use("/v1/today", todayRouter);
app.use("/v1/sleep", sleepRouter);
app.use("/v1/train", trainRouter);
app.use("/v1/body", bodyRouter);
app.use("/v1/coach", coachRouter);

if (process.env.NODE_ENV !== "test") {
  app.listen(env.PORT, () => {
    console.log(`readiness-coach API on :${env.PORT}`);
  });
}

export { app };
