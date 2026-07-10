import cors from "cors";
import express from "express";

const app = express();
app.use(cors());
app.use(express.json({ limit: "2mb" }));

app.get("/health", (_req, res) => {
  res.json({ ok: true });
});

const port = Number(process.env.PORT ?? 4000);
if (process.env.NODE_ENV !== "test") {
  app.listen(port, () => {
    console.log(`readiness-coach API on :${port}`);
  });
}

export { app };
