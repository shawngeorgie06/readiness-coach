import { Router } from "express";
import { applySync, syncPayloadSchema } from "../services/syncService.js";
import { AccountDeletedError } from "../services/userService.js";

export const syncRouter = Router();

syncRouter.post("/", async (req, res) => {
  const parsed = syncPayloadSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const userId = req.userId ?? "";
  if (!userId) {
    res.status(400).json({ error: "userId_required" });
    return;
  }

  try {
    const result = await applySync({ ...parsed.data, userId }, {
      restingHrBpm: 55,
      maxHrBpm: 190,
    });
    res.json(result);
  } catch (error) {
    if (error instanceof AccountDeletedError) {
      res.status(401).json({ error: "account_deleted" });
      return;
    }
    console.error(error);
    res.status(500).json({ error: "sync_failed" });
  }
});
