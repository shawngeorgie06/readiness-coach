import { prisma } from "../db.js";
import type { ResolveUserDeps } from "./resolveUser.js";

/** Prisma-backed implementation of ResolveUserDeps. */
export function prismaUserDeps(): ResolveUserDeps {
  return {
    findByAppleSub: (sub) => prisma.user.findUnique({ where: { appleSub: sub }, select: { id: true } }),
    findById: (id) => prisma.user.findUnique({ where: { id }, select: { id: true, appleSub: true } }),
    linkAppleSub: (userId, sub, email, displayName) =>
      prisma.user.update({
        where: { id: userId },
        data: { appleSub: sub, email, displayName },
        select: { id: true },
      }),
    createUser: (sub, email, displayName) =>
      prisma.user.create({ data: { appleSub: sub, email, displayName }, select: { id: true } }),
  };
}
