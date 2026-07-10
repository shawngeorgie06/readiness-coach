import { Prisma } from "@prisma/client";
import { prisma } from "../db.js";
import { UserNotFoundError } from "./todayService.js";

export async function deleteUser(userId: string): Promise<void> {
  try {
    await prisma.$transaction([
      prisma.advisorNote.deleteMany({ where: { userId } }),
      prisma.dailyScore.deleteMany({ where: { userId } }),
      prisma.workout.deleteMany({ where: { userId } }),
      prisma.healthSample.deleteMany({ where: { userId } }),
      prisma.user.delete({ where: { id: userId } }),
    ]);
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2025") {
      throw new UserNotFoundError(userId);
    }
    throw error;
  }
}
