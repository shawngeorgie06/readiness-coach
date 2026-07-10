import { Router } from "express";
import { UserNotFoundError } from "../services/todayService.js";
import { deleteUser } from "../services/userService.js";

export const userRouter = Router();

userRouter.delete("/", async (req, res) => {
  const userId = typeof req.query.userId === "string" ? req.query.userId : "";
  if (!userId) return res.status(400).json({ error: "userId_required" });

  try {
    await deleteUser(userId);
    return res.json({ ok: true });
  } catch (error) {
    if (error instanceof UserNotFoundError) return res.status(404).json({ error: "user_not_found" });
    console.error(error);
    return res.status(500).json({ error: "delete_failed" });
  }
});
