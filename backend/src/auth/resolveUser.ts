import type { AppleIdentity } from "./appleVerifier.js";

export interface ResolveUserDeps {
  findByAppleSub(sub: string): Promise<{ id: string } | null>;
  findById(id: string): Promise<{ id: string; appleSub: string | null } | null>;
  linkAppleSub(userId: string, sub: string, email?: string, displayName?: string): Promise<{ id: string }>;
  createUser(sub: string, email?: string, displayName?: string): Promise<{ id: string }>;
}

export interface ClaimInput {
  claimUserId?: string;
  claimToken?: string;
}

/**
 * Map an Apple identity to an internal user:
 * 1. Known Apple sub -> that user.
 * 2. Valid claim (token === apiToken, target exists and is unclaimed) -> link it.
 * 3. Otherwise -> create a fresh user. A failed claim never errors.
 */
export async function resolveUser(
  identity: AppleIdentity,
  displayName: string | undefined,
  claim: ClaimInput,
  apiToken: string,
  deps: ResolveUserDeps,
): Promise<{ id: string }> {
  const existing = await deps.findByAppleSub(identity.sub);
  if (existing) return existing;

  if (claim.claimUserId && claim.claimToken && claim.claimToken === apiToken) {
    const target = await deps.findById(claim.claimUserId);
    if (target && target.appleSub == null) {
      return deps.linkAppleSub(target.id, identity.sub, identity.email, displayName);
    }
  }

  return deps.createUser(identity.sub, identity.email, displayName);
}
