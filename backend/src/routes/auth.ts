import { Router } from "express";
import type { AppleVerifier } from "../auth/appleVerifier.js";
import { resolveUser, type ClaimInput, type ResolveUserDeps } from "../auth/resolveUser.js";
import { prismaUserDeps } from "../auth/prismaUserDeps.js";
import { mintSession } from "../auth/session.js";

export function createAuthRouter(opts: {
  verifier: AppleVerifier;
  sessionSecret: string;
  apiToken: string;
  deps?: ResolveUserDeps;
}): Router {
  const deps = opts.deps ?? prismaUserDeps();
  const router = Router();

  router.post("/apple", async (req, res) => {
    const body = (req.body ?? {}) as Record<string, unknown>;
    const identityToken = typeof body.identityToken === "string" ? body.identityToken : "";
    if (!identityToken) return res.status(400).json({ error: "identity_token_required" });

    let identity;
    try {
      identity = await opts.verifier.verify(identityToken);
    } catch {
      return res.status(401).json({ error: "invalid_apple_token" });
    }

    try {
      const displayName = typeof body.fullName === "string" && body.fullName.trim() ? body.fullName.trim() : undefined;
      const claim: ClaimInput = {
        claimUserId: typeof body.claimUserId === "string" ? body.claimUserId : undefined,
        claimToken: typeof body.claimToken === "string" ? body.claimToken : undefined,
      };

      const user = await resolveUser(identity, displayName, claim, opts.apiToken, deps);
      const sessionToken = await mintSession(user.id, opts.sessionSecret);
      return res.json({ sessionToken, userId: user.id });
    } catch (error) {
      console.error(error);
      return res.status(500).json({ error: "auth_failed" });
    }
  });

  return router;
}
