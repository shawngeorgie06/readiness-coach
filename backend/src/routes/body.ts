import { Router } from "express";
import { defaultRequestedDate, getBodyDetails } from "../services/todayService.js";

export const bodyRouter = Router();

bodyRouter.get("/", async (req, res) => {
  const userId = typeof req.query.userId === "string" ? req.query.userId : "";
  const days = req.query.days == null ? 30 : Number(req.query.days);
  if (!userId) return res.status(400).json({ error: "userId_required" });
  if (!Number.isInteger(days) || days < 1 || days > 90) return res.status(400).json({ error: "invalid_days" });
  try {
    return res.json(await getBodyDetails(userId, days, typeof req.query.date === "string" ? req.query.date : defaultRequestedDate()));
  } catch (error) {
    if (error instanceof Error && error.message === "date must be YYYY-MM-DD") return res.status(400).json({ error: "invalid_date" });
    console.error(error);
    return res.status(500).json({ error: "body_failed" });
  }
});
