import cors from "cors";
import express from "express";
import { loadEnv } from "./env.js";
import { requireToken } from "./middleware/auth.js";
import { syncRouter } from "./routes/sync.js";

const env = loadEnv();

const app = express();
app.use(cors());
app.use(express.json({ limit: "2mb" }));

app.get("/health", (_req, res) => {
  res.json({ ok: true });
});

app.use("/v1", requireToken(env.API_TOKEN));
app.use("/v1/sync", syncRouter);

if (process.env.NODE_ENV !== "test") {
  app.listen(env.PORT, () => {
    console.log(`readiness-coach API on :${env.PORT}`);
  });
}

export { app };
