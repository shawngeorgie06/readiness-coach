import { Router } from "express";
import { z } from "zod";
import { CoachUnavailableError, askCoach } from "../services/advisorService.js";
import { defaultRequestedDate, getToday, UserNotFoundError } from "../services/todayService.js";

const turnSchema = z.object({
  role: z.enum(["user", "assistant"]),
  content: z.string().trim().min(1).max(4_000),
});

export const askRequestSchema = z.object({
  userId: z.string().trim().min(1),
  question: z.string().trim().min(1).max(1_500),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  history: z.array(turnSchema).max(20).optional(),
});

export const coachRouter = Router();

coachRouter.post("/ask", async (req, res) => {
  const parsed = askRequestSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "invalid_request" });

  const userId = req.userId ?? "";
  if (!userId) return res.status(400).json({ error: "userId_required" });

  try {
    const today = await getToday(userId, parsed.data.date ?? defaultRequestedDate());
    const answer = await askCoach(parsed.data.question, today, parsed.data.history ?? []);
    return res.json({ decision: today.decision, answer });
  } catch (error) {
    if (error instanceof UserNotFoundError) return res.status(404).json({ error: "user_not_found" });
    if (error instanceof CoachUnavailableError) return res.status(503).json({ error: "coach_unavailable" });
    if (error instanceof Error && error.message === "date must be YYYY-MM-DD") {
      return res.status(400).json({ error: "invalid_date" });
    }
    console.error(error);
    return res.status(500).json({ error: "coach_failed" });
  }
});
