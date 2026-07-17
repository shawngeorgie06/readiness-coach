import { Router } from "express";
import { defaultRequestedDate, getReadinessHistory, UserNotFoundError } from "../services/todayService.js";

export const historyRouter = Router();

function daysFrom(value: unknown, fallback: number): number | undefined {
  if (value == null) return fallback;
  if (typeof value !== "string" || !/^\d+$/.test(value)) return undefined;
  const days = Number(value);
  return days >= 1 && days <= 90 ? days : undefined;
}

historyRouter.get("/", async (req, res) => {
  const userId = req.userId ?? "";
  const days = daysFrom(req.query.days, 30);
  if (!userId) return res.status(400).json({ error: "userId_required" });
  if (days == null) return res.status(400).json({ error: "invalid_days" });
  try {
    const date = typeof req.query.date === "string" ? req.query.date : defaultRequestedDate();
    return res.json(await getReadinessHistory(userId, days, date));
  } catch (error) {
    if (error instanceof UserNotFoundError) return res.status(404).json({ error: "user_not_found" });
    if (error instanceof Error && error.message === "date must be YYYY-MM-DD") {
      return res.status(400).json({ error: "invalid_date" });
    }
    console.error(error);
    return res.status(500).json({ error: "history_failed" });
  }
});
