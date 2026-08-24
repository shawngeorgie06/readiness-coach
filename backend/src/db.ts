import { PrismaClient } from "@prisma/client";

// Serverless invocations reuse a warm process — cache the client on globalThis so
// each request does not open a fresh connection pool against Postgres.
const globalForPrisma = globalThis as unknown as { prisma?: PrismaClient };

export const prisma = globalForPrisma.prisma ?? new PrismaClient();
globalForPrisma.prisma = prisma;
