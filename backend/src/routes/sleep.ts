import { Router } from "express";
import { defaultRequestedDate, getSleepDetails } from "../services/todayService.js";

export const sleepRouter = Router();

function daysFrom(value: unknown, fallback: number): number | undefined {
  if (value == null) return fallback;
  if (typeof value !== "string" || !/^\d+$/.test(value)) return undefined;
  const days = Number(value);
  return days >= 1 && days <= 90 ? days : undefined;
}

sleepRouter.get("/", async (req, res) => {
  const userId = typeof req.query.userId === "string" ? req.query.userId : "";
  const days = daysFrom(req.query.days, 30);
  if (!userId) return res.status(400).json({ error: "userId_required" });
  if (days == null) return res.status(400).json({ error: "invalid_days" });
  try {
    const tz = typeof req.query.tz === "string" && Number.isFinite(Number(req.query.tz)) ? Number(req.query.tz) : 0;
    return res.json(await getSleepDetails(userId, days, typeof req.query.date === "string" ? req.query.date : defaultRequestedDate(), tz));
  } catch (error) {
    if (error instanceof Error && error.message === "date must be YYYY-MM-DD") return res.status(400).json({ error: "invalid_date" });
    console.error(error);
    return res.status(500).json({ error: "sleep_failed" });
  }
});
