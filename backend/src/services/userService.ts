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
      // Tombstone prevents a still-valid session/token from re-creating the account on next sync.
      prisma.deletedUser.upsert({
        where: { userId },
        create: { userId },
        update: { deletedAt: new Date() },
      }),
    ]);
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2025") {
      throw new UserNotFoundError(userId);
    }
    throw error;
  }
}

export class AccountDeletedError extends Error {
  constructor(userId: string) {
    super(`Account ${userId} was deleted and cannot be re-created.`);
    this.name = "AccountDeletedError";
  }
}

export async function assertNotDeleted(userId: string): Promise<void> {
  const tombstone = await prisma.deletedUser.findUnique({ where: { userId } });
  if (tombstone) throw new AccountDeletedError(userId);
}
