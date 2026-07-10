import { Router } from "express";
import { applySync, syncPayloadSchema } from "../services/syncService.js";

export const syncRouter = Router();

syncRouter.post("/", async (req, res) => {
  const parsed = syncPayloadSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  try {
    const result = await applySync(parsed.data, {
      restingHrBpm: 55,
      maxHrBpm: 190,
    });
    res.json(result);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: "sync_failed" });
  }
});
