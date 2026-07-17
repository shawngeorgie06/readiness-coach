import { Router } from "express";
import { defaultRequestedDate, getToday, UserNotFoundError } from "../services/todayService.js";

export const todayRouter = Router();

todayRouter.get("/", async (req, res) => {
  const userId = req.userId ?? "";
  if (!userId) return res.status(400).json({ error: "userId_required" });

  try {
    const date = typeof req.query.date === "string" ? req.query.date : defaultRequestedDate();
    const tz = typeof req.query.tz === "string" && Number.isFinite(Number(req.query.tz)) ? Number(req.query.tz) : 0;
    return res.json(await getToday(userId, date, tz));
  } catch (error) {
    if (error instanceof UserNotFoundError) return res.status(404).json({ error: "user_not_found" });
    if (error instanceof Error && error.message === "date must be YYYY-MM-DD") {
      return res.status(400).json({ error: "invalid_date" });
    }
    console.error(error);
    return res.status(500).json({ error: "today_failed" });
  }
});
