# Sign in with Apple — Onboarding & Authentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace manual URL/token onboarding with Sign in with Apple, giving the app real per-user accounts while preserving the existing user's health history.

**Architecture:** The iOS app performs Sign in with Apple and posts the Apple identity token to a new unauthenticated `POST /v1/auth/apple`. The backend verifies the token against Apple's JWKS, resolves/claims/creates a `User` keyed by the Apple `sub`, and returns a self-signed 60-day session JWT. All other `/v1` routes move from a shared-token gate to a `requireSession` middleware that accepts the session JWT **or** (dual-mode, transitional) the legacy shared token + `?userId=`, so deploying the backend never breaks the currently-shipped app.

**Tech Stack:** Backend — Node 22, TypeScript, Express 4, Prisma 6, PostgreSQL, `jose` (JWT sign/verify + Apple JWKS), vitest, supertest. iOS — SwiftUI 17, AuthenticationServices (Sign in with Apple), Security (Keychain).

## Global Constraints

- Session JWT: `HS256`, signed with `SESSION_SECRET`, `expiresIn` **60d**, payload `{ userId }`. Copied verbatim into Task 3.
- Apple token verification MUST check: signature via Apple JWKS, `issuer === "https://appleid.apple.com"`, `audience === APPLE_BUNDLE_ID`, and expiry.
- New env vars: `SESSION_SECRET` (≥32 chars), `APPLE_BUNDLE_ID` (the iOS bundle identifier). `API_TOKEN` is **kept** (authorizes the one-time claim + legacy fallback).
- Schema migration is additive and nullable only (`appleSub`, `email`, `displayName`) — zero data-loss.
- Claim rule: link an existing user to an Apple `sub` **only if** `claimToken === API_TOKEN` AND the target user exists AND its `appleSub` is currently null. Otherwise create a new user. Never error on a failed claim — fall through to create.
- Routes read the caller's id from `req.userId` (set by middleware), never from client-supplied `req.query.userId` for the session path.
- Real data only; no change to scoring, sync payloads, or health-data handling.
- iOS `DEVELOPMENT_TEAM` (`X9G6H8M527`) stays **uncommitted**: before each iOS commit, `sed` it to `""`, commit, then `sed` it back. Never commit the team value.
- Backend commands run with `export PATH="$HOME/.local/node/bin:$PATH"` and from `~/readiness-coach/backend`.
- iOS build verification command:
  `xcodebuild -project ios/ReadinessCoach.xcodeproj -scheme ReadinessCoach -destination 'platform=iOS Simulator,id=FF54DD5B-1AE4-4603-B4AA-BAF6E6B519EE' build`

## File Structure

**Backend (create):**
- `backend/src/auth/session.ts` — mint/verify session JWTs.
- `backend/src/auth/appleVerifier.ts` — `AppleVerifier` interface + `createAppleVerifier`.
- `backend/src/auth/resolveUser.ts` — pure user resolve/claim/create logic.
- `backend/src/auth/prismaUserDeps.ts` — Prisma-backed `ResolveUserDeps`.
- `backend/src/routes/auth.ts` — `createAuthRouter` (`POST /v1/auth/apple`).
- `backend/src/types/express.d.ts` — augments `Express.Request` with `userId`.
- `backend/tests/auth/session.test.ts`, `backend/tests/auth/appleVerifier.test.ts`, `backend/tests/auth/resolveUser.test.ts`, `backend/tests/auth/authRoute.test.ts`, `backend/tests/auth/requireSession.test.ts`.

**Backend (modify):**
- `backend/prisma/schema.prisma` — add auth fields to `User`.
- `backend/src/env.ts` — add `SESSION_SECRET`, `APPLE_BUNDLE_ID`.
- `backend/src/middleware/auth.ts` — add `requireSession`.
- `backend/src/app.ts` — mount auth router, swap `requireToken`→`requireSession`, thread new options.
- `backend/src/index.ts` — pass new env into `createApp`.
- `backend/src/routes/{today,sleep,train,body,history,user,coach}.ts` — read `req.userId`.
- `backend/tests/app.test.ts` — update for new `createApp` options.

**iOS (create):**
- `ios/ReadinessCoach/Services/KeychainStore.swift` — Keychain string storage.
- `ios/ReadinessCoach/Services/AppleSignIn.swift` — Sign in with Apple → identity token.
- `ios/ReadinessCoach/ReadinessCoach.entitlements` — add Sign in with Apple entitlement (file already exists; add key).

**iOS (modify):**
- `ios/ReadinessCoach/Models/DTOs.swift` — auth request/response DTOs.
- `ios/ReadinessCoach/Networking/APIClient.swift` — `signInWithApple`, session-token bearer, 401 handling.
- `ios/ReadinessCoach/Settings/AppSettings.swift` — session token (Keychain), Apple display name, `signOut`.
- `ios/ReadinessCoach/Views/OnboardingView.swift` — redesign around Sign in with Apple.
- `ios/ReadinessCoach/Views/SettingsView.swift` — Account section + Sign out.
- `ios/ReadinessCoach.xcodeproj/project.pbxproj` — enable Sign in with Apple capability.

---

## Part A — Backend

### Task 1: Prisma schema — add Apple auth fields

**Files:**
- Modify: `backend/prisma/schema.prisma` (model `User`)

**Interfaces:**
- Produces: `User.appleSub: string | null` (`@unique`), `User.email: string | null`, `User.displayName: string | null` on the Prisma client.

- [ ] **Step 1: Add the fields to `model User`**

In `backend/prisma/schema.prisma`, inside `model User { ... }`, add these three lines after `settings Json?`:

```prisma
  appleSub    String? @unique
  email       String?
  displayName String?
```

- [ ] **Step 2: Validate the schema**

Run: `export PATH="$HOME/.local/node/bin:$PATH"; cd ~/readiness-coach/backend && npx prisma validate`
Expected: `The schema at prisma/schema.prisma is valid 🚀`

- [ ] **Step 3: Create and apply the migration**

Run: `export PATH="$HOME/.local/node/bin:$PATH"; cd ~/readiness-coach/backend && npx prisma migrate dev --name add_apple_auth`
Expected: a new folder under `prisma/migrations/*_add_apple_auth/` and `Your database is now in sync with your schema.`

- [ ] **Step 4: Regenerate the client and typecheck**

Run: `export PATH="$HOME/.local/node/bin:$PATH"; cd ~/readiness-coach/backend && npx prisma generate && npx tsc --noEmit`
Expected: no output from `tsc` (success).

- [ ] **Step 5: Commit**

```bash
cd ~/readiness-coach && git add backend/prisma/schema.prisma backend/prisma/migrations && git commit -m "feat(auth): add appleSub/email/displayName to User"
```

---

### Task 2: Env — add SESSION_SECRET and APPLE_BUNDLE_ID

**Files:**
- Modify: `backend/src/env.ts`
- Test: `backend/tests/auth/env.test.ts` (create)

**Interfaces:**
- Produces: `Env.SESSION_SECRET: string`, `Env.APPLE_BUNDLE_ID: string`.

- [ ] **Step 1: Write the failing test**

Create `backend/tests/auth/env.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { loadEnv } from "../../src/env.js";

const base = {
  DATABASE_URL: "postgres://x",
  API_TOKEN: "token-1234",
  SESSION_SECRET: "a".repeat(32),
  APPLE_BUNDLE_ID: "com.example.app",
};

describe("loadEnv auth vars", () => {
  it("parses SESSION_SECRET and APPLE_BUNDLE_ID", () => {
    const env = loadEnv(base as NodeJS.ProcessEnv);
    expect(env.SESSION_SECRET).toBe("a".repeat(32));
    expect(env.APPLE_BUNDLE_ID).toBe("com.example.app");
  });

  it("rejects a short SESSION_SECRET", () => {
    expect(() => loadEnv({ ...base, SESSION_SECRET: "short" } as NodeJS.ProcessEnv)).toThrow(/Invalid env/);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `export PATH="$HOME/.local/node/bin:$PATH"; cd ~/readiness-coach/backend && npx vitest run tests/auth/env.test.ts`
Expected: FAIL (`SESSION_SECRET` undefined / property missing).

- [ ] **Step 3: Add the fields to the schema**

In `backend/src/env.ts`, add to the `envSchema` object (after `API_TOKEN`):

```ts
  SESSION_SECRET: z.string().min(32),
  APPLE_BUNDLE_ID: z.string().min(1),
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `export PATH="$HOME/.local/node/bin:$PATH"; cd ~/readiness-coach/backend && npx vitest run tests/auth/env.test.ts`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/readiness-coach && git add backend/src/env.ts backend/tests/auth/env.test.ts && git commit -m "feat(auth): require SESSION_SECRET and APPLE_BUNDLE_ID env"
```

---

### Task 3: Session tokens (jose HS256 mint/verify)

**Files:**
- Create: `backend/src/auth/session.ts`
- Test: `backend/tests/auth/session.test.ts`

**Interfaces:**
- Produces: `mintSession(userId: string, secret: string, ttl?: string): Promise<string>`; `verifySession(token: string, secret: string): Promise<string | null>` (returns the `userId`, or `null` on any failure).

- [ ] **Step 1: Add the `jose` dependency**

Run: `export PATH="$HOME/.local/node/bin:$PATH"; cd ~/readiness-coach/backend && npm install jose@5`
Expected: `jose` appears in `package.json` dependencies.

- [ ] **Step 2: Write the failing test**

Create `backend/tests/auth/session.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { mintSession, verifySession } from "../../src/auth/session.js";

const secret = "s".repeat(32);

describe("session tokens", () => {
  it("round-trips the userId", async () => {
    const token = await mintSession("user-123", secret);
    expect(await verifySession(token, secret)).toBe("user-123");
  });

  it("rejects a token signed with a different secret", async () => {
    const token = await mintSession("user-123", secret);
    expect(await verifySession(token, "d".repeat(32))).toBeNull();
  });

  it("rejects an expired token", async () => {
    const token = await mintSession("user-123", secret, "0s");
    // allow the exp claim (whole-second granularity) to pass
    await new Promise((r) => setTimeout(r, 1100));
    expect(await verifySession(token, secret)).toBeNull();
  });

  it("returns null for garbage", async () => {
    expect(await verifySession("not-a-jwt", secret)).toBeNull();
  });
});
```

- [ ] **Step 3: Run it to verify it fails**

Run: `export PATH="$HOME/.local/node/bin:$PATH"; cd ~/readiness-coach/backend && npx vitest run tests/auth/session.test.ts`
Expected: FAIL (cannot find module `session.js`).

- [ ] **Step 4: Implement**

Create `backend/src/auth/session.ts`:

```ts
import { SignJWT, jwtVerify } from "jose";

function key(secret: string): Uint8Array {
  return new TextEncoder().encode(secret);
}

/** Sign a 60-day session token carrying the internal userId. */
export async function mintSession(userId: string, secret: string, ttl = "60d"): Promise<string> {
  return new SignJWT({ userId })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuedAt()
    .setExpirationTime(ttl)
    .sign(key(secret));
}

/** Verify a session token; returns the userId, or null on any failure. */
export async function verifySession(token: string, secret: string): Promise<string | null> {
  try {
    const { payload } = await jwtVerify(token, key(secret));
    return typeof payload.userId === "string" ? payload.userId : null;
  } catch {
    return null;
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `export PATH="$HOME/.local/node/bin:$PATH"; cd ~/readiness-coach/backend && npx vitest run tests/auth/session.test.ts`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
cd ~/readiness-coach && git add backend/package.json backend/package-lock.json backend/src/auth/session.ts backend/tests/auth/session.test.ts && git commit -m "feat(auth): session JWT mint/verify"
```

---

### Task 4: Apple identity-token verifier

**Files:**
- Create: `backend/src/auth/appleVerifier.ts`
- Test: `backend/tests/auth/appleVerifier.test.ts`

**Interfaces:**
- Produces: `interface AppleIdentity { sub: string; email?: string }`; `interface AppleVerifier { verify(identityToken: string): Promise<AppleIdentity> }`; `createAppleVerifier(opts: { bundleId: string; getKey?: JWKSResolver }): AppleVerifier` where `JWKSResolver` is jose's second `jwtVerify` argument (a `KeyLike`/`Uint8Array`/`JWTVerifyGetKey`). `verify` throws on any invalid token.

- [ ] **Step 1: Write the failing test**

Create `backend/tests/auth/appleVerifier.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { SignJWT, generateKeyPair } from "jose";
import { createAppleVerifier } from "../../src/auth/appleVerifier.js";

const BUNDLE = "com.example.readiness";
const ISSUER = "https://appleid.apple.com";

async function fixture() {
  const { publicKey, privateKey } = await generateKeyPair("RS256");
  const sign = (claims: { aud?: string; iss?: string; sub?: string; email?: string; exp?: string }) =>
    new SignJWT({ email: claims.email })
      .setProtectedHeader({ alg: "RS256" })
      .setIssuer(claims.iss ?? ISSUER)
      .setAudience(claims.aud ?? BUNDLE)
      .setSubject(claims.sub ?? "apple-sub-1")
      .setIssuedAt()
      .setExpirationTime(claims.exp ?? "5m")
      .sign(privateKey);
  const verifier = createAppleVerifier({ bundleId: BUNDLE, getKey: publicKey });
  return { sign, verifier };
}

describe("createAppleVerifier", () => {
  it("accepts a valid token and returns sub + email", async () => {
    const { sign, verifier } = await fixture();
    const token = await sign({ email: "me@example.com" });
    expect(await verifier.verify(token)).toEqual({ sub: "apple-sub-1", email: "me@example.com" });
  });

  it("rejects a wrong audience", async () => {
    const { sign, verifier } = await fixture();
    const token = await sign({ aud: "com.someone.else" });
    await expect(verifier.verify(token)).rejects.toThrow();
  });

  it("rejects a wrong issuer", async () => {
    const { sign, verifier } = await fixture();
    const token = await sign({ iss: "https://evil.example" });
    await expect(verifier.verify(token)).rejects.toThrow();
  });

  it("rejects an expired token", async () => {
    const { sign, verifier } = await fixture();
    const token = await sign({ exp: "0s" });
    await new Promise((r) => setTimeout(r, 1100));
    await expect(verifier.verify(token)).rejects.toThrow();
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `export PATH="$HOME/.local/node/bin:$PATH"; cd ~/readiness-coach/backend && npx vitest run tests/auth/appleVerifier.test.ts`
Expected: FAIL (cannot find module `appleVerifier.js`).

- [ ] **Step 3: Implement**

Create `backend/src/auth/appleVerifier.ts`:

```ts
import { createRemoteJWKSet, jwtVerify } from "jose";

export interface AppleIdentity {
  sub: string;
  email?: string;
}

export interface AppleVerifier {
  verify(identityToken: string): Promise<AppleIdentity>;
}

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys";

// jose's second jwtVerify arg: a key or a key-resolver. Kept loose so tests can
// inject a public key directly instead of hitting Apple's JWKS endpoint.
type KeyInput = Parameters<typeof jwtVerify>[1];

export function createAppleVerifier(opts: { bundleId: string; getKey?: KeyInput }): AppleVerifier {
  const getKey: KeyInput = opts.getKey ?? createRemoteJWKSet(new URL(APPLE_JWKS_URL));
  return {
    async verify(identityToken: string): Promise<AppleIdentity> {
      const { payload } = await jwtVerify(identityToken, getKey as never, {
        issuer: APPLE_ISSUER,
        audience: opts.bundleId,
      });
      if (typeof payload.sub !== "string" || payload.sub.length === 0) {
        throw new Error("apple identity token missing sub");
      }
      const email = typeof payload.email === "string" ? payload.email : undefined;
      return { sub: payload.sub, email };
    },
  };
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `export PATH="$HOME/.local/node/bin:$PATH"; cd ~/readiness-coach/backend && npx vitest run tests/auth/appleVerifier.test.ts`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/readiness-coach && git add backend/src/auth/appleVerifier.ts backend/tests/auth/appleVerifier.test.ts && git commit -m "feat(auth): verify Apple identity tokens against JWKS"
```

---

### Task 5: resolveUser — pure resolve/claim/create logic

**Files:**
- Create: `backend/src/auth/resolveUser.ts`
- Test: `backend/tests/auth/resolveUser.test.ts`

**Interfaces:**
- Consumes: `AppleIdentity` from Task 4.
- Produces:
  - `interface ResolveUserDeps { findByAppleSub(sub): Promise<{ id: string } | null>; findById(id): Promise<{ id: string; appleSub: string | null } | null>; linkAppleSub(userId, sub, email?, displayName?): Promise<{ id: string }>; createUser(sub, email?, displayName?): Promise<{ id: string }> }`
  - `interface ClaimInput { claimUserId?: string; claimToken?: string }`
  - `resolveUser(identity: AppleIdentity, displayName: string | undefined, claim: ClaimInput, apiToken: string, deps: ResolveUserDeps): Promise<{ id: string }>`

- [ ] **Step 1: Write the failing test**

Create `backend/tests/auth/resolveUser.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { resolveUser, type ResolveUserDeps } from "../../src/auth/resolveUser.js";

const API_TOKEN = "shared-token";

function makeDeps(overrides: Partial<ResolveUserDeps> = {}) {
  const calls = { created: [] as unknown[], linked: [] as unknown[] };
  const deps: ResolveUserDeps = {
    findByAppleSub: async () => null,
    findById: async () => null,
    linkAppleSub: async (userId) => { calls.linked.push(userId); return { id: userId }; },
    createUser: async () => { calls.created.push("new"); return { id: "new-user" }; },
    ...overrides,
  };
  return { deps, calls };
}

describe("resolveUser", () => {
  it("returns the existing user when the Apple sub is already mapped", async () => {
    const { deps, calls } = makeDeps({ findByAppleSub: async () => ({ id: "known" }) });
    expect(await resolveUser({ sub: "s1" }, undefined, {}, API_TOKEN, deps)).toEqual({ id: "known" });
    expect(calls.created).toHaveLength(0);
    expect(calls.linked).toHaveLength(0);
  });

  it("claims an existing unclaimed user with a valid token", async () => {
    const { deps, calls } = makeDeps({
      findById: async () => ({ id: "legacy", appleSub: null }),
    });
    const user = await resolveUser({ sub: "s1", email: "a@b.c" }, "Sam",
      { claimUserId: "legacy", claimToken: API_TOKEN }, API_TOKEN, deps);
    expect(user).toEqual({ id: "legacy" });
    expect(calls.linked).toEqual(["legacy"]);
    expect(calls.created).toHaveLength(0);
  });

  it("creates a new user when the claim token is wrong", async () => {
    const { deps, calls } = makeDeps({
      findById: async () => ({ id: "legacy", appleSub: null }),
    });
    const user = await resolveUser({ sub: "s1" }, undefined,
      { claimUserId: "legacy", claimToken: "WRONG" }, API_TOKEN, deps);
    expect(user).toEqual({ id: "new-user" });
    expect(calls.linked).toHaveLength(0);
    expect(calls.created).toHaveLength(1);
  });

  it("creates a new user when the target already has an appleSub", async () => {
    const { deps, calls } = makeDeps({
      findById: async () => ({ id: "legacy", appleSub: "someone-else" }),
    });
    const user = await resolveUser({ sub: "s1" }, undefined,
      { claimUserId: "legacy", claimToken: API_TOKEN }, API_TOKEN, deps);
    expect(user).toEqual({ id: "new-user" });
    expect(calls.linked).toHaveLength(0);
  });

  it("creates a new user when there is no claim", async () => {
    const { deps, calls } = makeDeps();
    expect(await resolveUser({ sub: "s1" }, undefined, {}, API_TOKEN, deps)).toEqual({ id: "new-user" });
    expect(calls.created).toHaveLength(1);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `export PATH="$HOME/.local/node/bin:$PATH"; cd ~/readiness-coach/backend && npx vitest run tests/auth/resolveUser.test.ts`
Expected: FAIL (cannot find module `resolveUser.js`).

- [ ] **Step 3: Implement**

Create `backend/src/auth/resolveUser.ts`:

```ts
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `export PATH="$HOME/.local/node/bin:$PATH"; cd ~/readiness-coach/backend && npx vitest run tests/auth/resolveUser.test.ts`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/readiness-coach && git add backend/src/auth/resolveUser.ts backend/tests/auth/resolveUser.test.ts && git commit -m "feat(auth): resolveUser resolve/claim/create logic"
```

---

### Task 6: Prisma-backed ResolveUserDeps

**Files:**
- Create: `backend/src/auth/prismaUserDeps.ts`

**Interfaces:**
- Consumes: `ResolveUserDeps` from Task 5, `prisma` from `backend/src/db.ts`.
- Produces: `prismaUserDeps(): ResolveUserDeps`.

- [ ] **Step 1: Implement (thin Prisma adapter — verified by Task 8's route test and typecheck)**

Create `backend/src/auth/prismaUserDeps.ts`:

```ts
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
```

- [ ] **Step 2: Typecheck**

Run: `export PATH="$HOME/.local/node/bin:$PATH"; cd ~/readiness-coach/backend && npx tsc --noEmit`
Expected: no output (success). If `appleSub` is not a known `where` field, Task 1's `prisma generate` did not run — re-run it.

- [ ] **Step 3: Commit**

```bash
cd ~/readiness-coach && git add backend/src/auth/prismaUserDeps.ts && git commit -m "feat(auth): Prisma-backed ResolveUserDeps"
```

---

### Task 7: `POST /v1/auth/apple` route

**Files:**
- Create: `backend/src/routes/auth.ts`
- Test: `backend/tests/auth/authRoute.test.ts`

**Interfaces:**
- Consumes: `AppleVerifier` (Task 4), `resolveUser`/`ResolveUserDeps` (Task 5), `mintSession` (Task 3).
- Produces: `createAuthRouter(opts: { verifier: AppleVerifier; sessionSecret: string; apiToken: string; deps?: ResolveUserDeps }): Router`. Route `POST /apple` accepts `{ identityToken, fullName?, claimUserId?, claimToken? }`, returns `{ sessionToken, userId }` (200), `400 { error: "identity_token_required" }`, or `401 { error: "invalid_apple_token" }`.

- [ ] **Step 1: Write the failing test**

Create `backend/tests/auth/authRoute.test.ts`:

```ts
import express from "express";
import request from "supertest";
import { describe, expect, it } from "vitest";
import { createAuthRouter } from "../../src/routes/auth.js";
import { verifySession } from "../../src/auth/session.js";
import type { AppleVerifier } from "../../src/auth/appleVerifier.js";
import type { ResolveUserDeps } from "../../src/auth/resolveUser.js";

const SECRET = "x".repeat(32);
const API_TOKEN = "shared-token";

function appWith(verifier: AppleVerifier, deps: ResolveUserDeps) {
  const app = express();
  app.use(express.json());
  app.use("/v1/auth", createAuthRouter({ verifier, sessionSecret: SECRET, apiToken: API_TOKEN, deps }));
  return app;
}

const okVerifier: AppleVerifier = { verify: async () => ({ sub: "apple-1", email: "a@b.c" }) };
const newUserDeps: ResolveUserDeps = {
  findByAppleSub: async () => null,
  findById: async () => null,
  linkAppleSub: async (id) => ({ id }),
  createUser: async () => ({ id: "created-user" }),
};

describe("POST /v1/auth/apple", () => {
  it("400s without an identity token", async () => {
    await request(appWith(okVerifier, newUserDeps)).post("/v1/auth/apple").send({}).expect(400, { error: "identity_token_required" });
  });

  it("401s on an invalid Apple token", async () => {
    const bad: AppleVerifier = { verify: async () => { throw new Error("bad"); } };
    await request(appWith(bad, newUserDeps)).post("/v1/auth/apple").send({ identityToken: "x" }).expect(401, { error: "invalid_apple_token" });
  });

  it("returns a valid session token for a new user", async () => {
    const res = await request(appWith(okVerifier, newUserDeps)).post("/v1/auth/apple").send({ identityToken: "x" }).expect(200);
    expect(res.body.userId).toBe("created-user");
    expect(await verifySession(res.body.sessionToken, SECRET)).toBe("created-user");
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `export PATH="$HOME/.local/node/bin:$PATH"; cd ~/readiness-coach/backend && npx vitest run tests/auth/authRoute.test.ts`
Expected: FAIL (cannot find module `auth.js`).

- [ ] **Step 3: Implement**

Create `backend/src/routes/auth.ts`:

```ts
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

    const displayName = typeof body.fullName === "string" && body.fullName.trim() ? body.fullName.trim() : undefined;
    const claim: ClaimInput = {
      claimUserId: typeof body.claimUserId === "string" ? body.claimUserId : undefined,
      claimToken: typeof body.claimToken === "string" ? body.claimToken : undefined,
    };

    const user = await resolveUser(identity, displayName, claim, opts.apiToken, deps);
    const sessionToken = await mintSession(user.id, opts.sessionSecret);
    return res.json({ sessionToken, userId: user.id });
  });

  return router;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `export PATH="$HOME/.local/node/bin:$PATH"; cd ~/readiness-coach/backend && npx vitest run tests/auth/authRoute.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/readiness-coach && git add backend/src/routes/auth.ts backend/tests/auth/authRoute.test.ts && git commit -m "feat(auth): POST /v1/auth/apple endpoint"
```

---

### Task 8: `requireSession` middleware (dual-mode) + Request type

**Files:**
- Create: `backend/src/types/express.d.ts`
- Modify: `backend/src/middleware/auth.ts`
- Test: `backend/tests/auth/requireSession.test.ts`

**Interfaces:**
- Consumes: `verifySession` (Task 3).
- Produces: `requireSession(opts: { sessionSecret: string; apiToken: string }): RequestHandler` — sets `req.userId` from a valid session JWT, else (legacy) from `req.query.userId`/`req.body.userId` when the bearer equals `apiToken`, else `401 { error: "unauthorized" }`. `Express.Request.userId?: string` is declared globally.

- [ ] **Step 1: Declare `req.userId`**

Create `backend/src/types/express.d.ts`:

```ts
declare global {
  namespace Express {
    interface Request {
      userId?: string;
    }
  }
}

export {};
```

- [ ] **Step 2: Write the failing test**

Create `backend/tests/auth/requireSession.test.ts`:

```ts
import express from "express";
import request from "supertest";
import { describe, expect, it } from "vitest";
import { requireSession } from "../../src/middleware/auth.js";
import { mintSession } from "../../src/auth/session.js";

const SECRET = "z".repeat(32);
const API_TOKEN = "shared-token";

function app() {
  const a = express();
  a.use(express.json());
  a.use(requireSession({ sessionSecret: SECRET, apiToken: API_TOKEN }));
  a.get("/probe", (req, res) => res.json({ userId: req.userId ?? null }));
  return a;
}

describe("requireSession", () => {
  it("401s without a bearer", async () => {
    await request(app()).get("/probe").expect(401, { error: "unauthorized" });
  });

  it("accepts a session JWT and sets req.userId", async () => {
    const token = await mintSession("user-9", SECRET);
    await request(app()).get("/probe").set("Authorization", `Bearer ${token}`).expect(200, { userId: "user-9" });
  });

  it("accepts the legacy shared token with a query userId", async () => {
    await request(app()).get("/probe?userId=legacy-7").set("Authorization", `Bearer ${API_TOKEN}`).expect(200, { userId: "legacy-7" });
  });

  it("401s on an unknown bearer", async () => {
    await request(app()).get("/probe").set("Authorization", "Bearer nope").expect(401, { error: "unauthorized" });
  });
});
```

- [ ] **Step 3: Run it to verify it fails**

Run: `export PATH="$HOME/.local/node/bin:$PATH"; cd ~/readiness-coach/backend && npx vitest run tests/auth/requireSession.test.ts`
Expected: FAIL (`requireSession` not exported).

- [ ] **Step 4: Implement**

In `backend/src/middleware/auth.ts`, add (keep the existing `requireToken` export as-is):

```ts
import { verifySession } from "../auth/session.js";

/**
 * Authenticate a /v1 request. Prefers a session JWT (sets req.userId from its
 * payload). Falls back, during migration, to the legacy shared token plus an
 * explicit ?userId= / body userId. Anything else is 401.
 */
export function requireSession(opts: { sessionSecret: string; apiToken: string }) {
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    const header = req.header("authorization") ?? "";
    const token = header.startsWith("Bearer ") ? header.slice(7) : "";
    if (!token) {
      res.status(401).json({ error: "unauthorized" });
      return;
    }

    const sessionUserId = await verifySession(token, opts.sessionSecret);
    if (sessionUserId) {
      req.userId = sessionUserId;
      next();
      return;
    }

    if (token === opts.apiToken) {
      const query = typeof req.query.userId === "string" ? req.query.userId : "";
      const bodyUserId =
        req.body != null && typeof (req.body as Record<string, unknown>).userId === "string"
          ? ((req.body as Record<string, unknown>).userId as string)
          : "";
      req.userId = query || bodyUserId;
      next();
      return;
    }

    res.status(401).json({ error: "unauthorized" });
  };
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `export PATH="$HOME/.local/node/bin:$PATH"; cd ~/readiness-coach/backend && npx vitest run tests/auth/requireSession.test.ts`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
cd ~/readiness-coach && git add backend/src/types/express.d.ts backend/src/middleware/auth.ts backend/tests/auth/requireSession.test.ts && git commit -m "feat(auth): requireSession dual-mode middleware"
```

---

### Task 9: Wire the app — mount auth router, swap middleware, read req.userId

**Files:**
- Modify: `backend/src/app.ts`, `backend/src/index.ts`
- Modify: `backend/src/routes/{today,sleep,train,body,history,user}.ts` and `backend/src/routes/coach.ts`
- Modify: `backend/tests/app.test.ts`

**Interfaces:**
- Consumes: `createAuthRouter` (Task 7), `requireSession` (Task 8), `createAppleVerifier` (Task 4).
- Produces: `createApp` gains options `sessionSecret: string`, `appleBundleId?: string`, `appleVerifier?: AppleVerifier`. Every `/v1` route (except `/v1/auth`) reads `req.userId`.

- [ ] **Step 1: Update `createApp`**

In `backend/src/app.ts`:

Add imports near the other route imports:

```ts
import { requireToken, requireSession } from "./middleware/auth.js";
import { createAuthRouter } from "./routes/auth.js";
import { createAppleVerifier, type AppleVerifier } from "./auth/appleVerifier.js";
```
(Replace the existing `import { requireToken } from "./middleware/auth.js";` line.)

Extend `AppOptions`:

```ts
export interface AppOptions {
  apiToken: string;
  sessionSecret: string;
  appleBundleId?: string;
  appleVerifier?: AppleVerifier;
  checkDatabase?: () => Promise<unknown>;
  corsOrigin?: string;
  rateLimit?: RateLimitOptions;
}
```

In the `createApp` destructure, add `sessionSecret`, `appleBundleId`, `appleVerifier`. Then replace the auth wiring block:

```ts
  app.use(
    "/v1",
    rateLimit({
      windowMs: rateLimitOptions.windowMs,
      limit: rateLimitOptions.max,
      standardHeaders: true,
      legacyHeaders: false,
    }),
  );

  // Login endpoint is unauthenticated; it issues the session token.
  const verifier = appleVerifier ?? (appleBundleId ? createAppleVerifier({ bundleId: appleBundleId }) : undefined);
  if (verifier) {
    app.use("/v1/auth", createAuthRouter({ verifier, sessionSecret, apiToken }));
  }

  // Everything else requires a session (or the legacy shared token).
  app.use("/v1", requireSession({ sessionSecret, apiToken }));
  app.use("/v1/sync", syncRouter);
  app.use("/v1/today", todayRouter);
  app.use("/v1/history", historyRouter);
  app.use("/v1/sleep", sleepRouter);
  app.use("/v1/train", trainRouter);
  app.use("/v1/body", bodyRouter);
  app.use("/v1/coach", coachRouter);
  app.use("/v1/user", userRouter);
```

Note: `requireToken` stays imported/exported for back-compat but is no longer mounted. Remove the old `app.use("/v1", requireToken(apiToken));` line.

- [ ] **Step 2: Update `index.ts`**

In `backend/src/index.ts`, change the `createApp` call to pass the new env:

```ts
const app = createApp({
  apiToken: env.API_TOKEN,
  sessionSecret: env.SESSION_SECRET,
  appleBundleId: env.APPLE_BUNDLE_ID,
  corsOrigin: env.CORS_ORIGIN,
});
```

- [ ] **Step 3: Change every route to read `req.userId`**

In each of `today.ts`, `sleep.ts`, `train.ts`, `body.ts`, `history.ts`, `user.ts`, replace the line:

```ts
  const userId = typeof req.query.userId === "string" ? req.query.userId : "";
```
with:
```ts
  const userId = req.userId ?? "";
```

In `backend/src/routes/coach.ts`, the userId comes from the zod body. Replace the handler's user id source: after `const parsed = ...`, use `req.userId ?? ""` instead of `parsed.data.userId`. Concretely, remove `userId` from the zod schema's required fields is not necessary; instead change the call:

```ts
    const userId = req.userId ?? "";
    if (!userId) return res.status(400).json({ error: "userId_required" });
    const today = await getToday(userId, parsed.data.date ?? defaultRequestedDate());
```
and pass `userId` (not `parsed.data.userId`) everywhere else in that handler that used the body userId.

- [ ] **Step 4: Update `app.test.ts` for the new options**

In `backend/tests/app.test.ts`, add `sessionSecret: "t".repeat(32),` to **every** `createApp({ ... })` call object. The existing auth expectations still hold: no bearer → 401; wrong bearer → 401; `Bearer test-api-token` + no userId → `400 userId_required` (legacy path sets `req.userId = ""`, route guard returns 400).

- [ ] **Step 5: Run the full backend suite + typecheck**

Run: `export PATH="$HOME/.local/node/bin:$PATH"; cd ~/readiness-coach/backend && npx tsc --noEmit && npx vitest run`
Expected: `tsc` clean; all tests pass (existing + new auth tests). If an integration test in `tests/integration/api.test.ts` sets `Authorization` with the shared token and `?userId=`, it still passes via dual-mode; if it constructs `createApp`, add `sessionSecret`.

- [ ] **Step 6: Commit**

```bash
cd ~/readiness-coach && git add backend/src/app.ts backend/src/index.ts backend/src/routes backend/tests/app.test.ts && git commit -m "feat(auth): mount auth router, gate /v1 with requireSession, read req.userId"
```

---

## Part B — iOS

> iOS has no unit-test target; each iOS task's deliverable is verified by a successful `xcodebuild ... build`. Before every iOS commit, blank the signing team, commit, then restore it (see Global Constraints).

### Task 10: Keychain session store

**Files:**
- Create: `ios/ReadinessCoach/Services/KeychainStore.swift`

**Interfaces:**
- Produces: `enum KeychainStore { static func set(_ value: String, for key: String); static func get(_ key: String) -> String?; static func remove(_ key: String) }`.

- [ ] **Step 1: Implement**

Create `ios/ReadinessCoach/Services/KeychainStore.swift`:

```swift
import Foundation
import Security

/// Minimal Keychain wrapper for storing credential strings (the session token).
/// Generic-password items keyed by a string account name.
enum KeychainStore {
    private static let service = "com.readinesscoach.session"

    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

- [ ] **Step 2: Build**

Run the iOS build command (Global Constraints). Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit** (blank team → commit → restore team)

```bash
cd ~/readiness-coach
sed -i '' 's/DEVELOPMENT_TEAM = X9G6H8M527;/DEVELOPMENT_TEAM = "";/g' ios/ReadinessCoach.xcodeproj/project.pbxproj
git add ios/ReadinessCoach/Services/KeychainStore.swift ios/ReadinessCoach.xcodeproj/project.pbxproj
git commit -m "feat(auth): Keychain session store (iOS)"
sed -i '' 's/DEVELOPMENT_TEAM = "";/DEVELOPMENT_TEAM = X9G6H8M527;/g' ios/ReadinessCoach.xcodeproj/project.pbxproj
```

---

### Task 11: Auth DTOs + APIClient sign-in and session bearer

**Files:**
- Modify: `ios/ReadinessCoach/Models/DTOs.swift`
- Modify: `ios/ReadinessCoach/Networking/APIClient.swift`

**Interfaces:**
- Produces: `struct AppleAuthRequest: Codable { let identityToken: String; let fullName: String?; let claimUserId: String?; let claimToken: String? }`; `struct AuthResponse: Codable { let sessionToken: String; let userId: String }`; `APIClient.signInWithApple(identityToken:fullName:claimUserId:claimToken:) async throws -> AuthResponse`. `APIClient` sends `Authorization: Bearer <token>` where `token` is the session token when present.

- [ ] **Step 1: Add DTOs**

In `ios/ReadinessCoach/Models/DTOs.swift`, append:

```swift
// MARK: - Auth

struct AppleAuthRequest: Codable {
    let identityToken: String
    let fullName: String?
    let claimUserId: String?
    let claimToken: String?
}

struct AuthResponse: Codable {
    let sessionToken: String
    let userId: String
}
```

- [ ] **Step 2: Add the sign-in call to `APIClient`**

In `ios/ReadinessCoach/Networking/APIClient.swift`, add inside `struct APIClient` (after `ask(...)`):

```swift
    /// Exchanges an Apple identity token for a backend session. Unauthenticated
    /// (no bearer required); optionally claims an existing user's history.
    func signInWithApple(
        identityToken: String,
        fullName: String?,
        claimUserId: String?,
        claimToken: String?
    ) async throws -> AuthResponse {
        let body = AppleAuthRequest(
            identityToken: identityToken,
            fullName: fullName,
            claimUserId: claimUserId,
            claimToken: claimToken
        )
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/auth/apple"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.encoder.encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.http(status: -1, code: nil) }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, code: Self.errorCode(from: data))
        }
        return try decode(data)
    }
```

The existing `requestData` already sends `Authorization: Bearer \(token)`. In the session world, `token` holds the session token (see Task 13/14 which set `APIClient.token` from the stored session token). No change to `requestData` is required for the bearer.

- [ ] **Step 3: Build**

Run the iOS build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit** (blank team → commit → restore team)

```bash
cd ~/readiness-coach
sed -i '' 's/DEVELOPMENT_TEAM = X9G6H8M527;/DEVELOPMENT_TEAM = "";/g' ios/ReadinessCoach.xcodeproj/project.pbxproj
git add ios/ReadinessCoach/Models/DTOs.swift ios/ReadinessCoach/Networking/APIClient.swift ios/ReadinessCoach.xcodeproj/project.pbxproj
git commit -m "feat(auth): APIClient Apple sign-in + auth DTOs (iOS)"
sed -i '' 's/DEVELOPMENT_TEAM = "";/DEVELOPMENT_TEAM = X9G6H8M527;/g' ios/ReadinessCoach.xcodeproj/project.pbxproj
```

---

### Task 12: AppSettings — session token, display name, sign out

**Files:**
- Modify: `ios/ReadinessCoach/Settings/AppSettings.swift`

**Interfaces:**
- Consumes: `KeychainStore` (Task 10), `AuthResponse` (Task 11).
- Produces: on `AppSettings` — `var sessionToken: String?` (Keychain-backed, published), `@Published var appleDisplayName: String?`, `var isSignedIn: Bool { sessionToken != nil }`, `func applyAuth(_ response: AuthResponse, displayName: String?)`, `func signOut()`. `makeClient()` uses the session token as the bearer when signed in.

- [ ] **Step 1: Add session storage**

In `ios/ReadinessCoach/Settings/AppSettings.swift`, add these members (keys `"sessionToken"` in Keychain; `appleDisplayName`/`userId` in UserDefaults as the file already does for settings):

```swift
    private let sessionKey = "sessionToken"

    /// The backend session token (Keychain-backed). Nil when signed out.
    var sessionToken: String? {
        get { KeychainStore.get(sessionKey) }
        set {
            if let newValue { KeychainStore.set(newValue, for: sessionKey) }
            else { KeychainStore.remove(sessionKey) }
            objectWillChange.send()
        }
    }

    @Published var appleDisplayName: String? {
        didSet { UserDefaults.standard.set(appleDisplayName, forKey: "appleDisplayName") }
    }

    var isSignedIn: Bool { sessionToken != nil }

    /// Persist a successful Apple sign-in: session token, userId, display name.
    func applyAuth(_ response: AuthResponse, displayName: String?) {
        userId = response.userId
        if let displayName, !displayName.isEmpty { appleDisplayName = displayName }
        sessionToken = response.sessionToken
    }

    /// Clear the session (returns the app to the sign-in screen).
    func signOut() {
        sessionToken = nil
        appleDisplayName = nil
        hasCompletedOnboarding = false
    }
```

Initialize `appleDisplayName` in `init()` from `UserDefaults.standard.string(forKey: "appleDisplayName")`.

- [ ] **Step 2: Make the client use the session token**

Locate `makeClient()` in `AppSettings.swift`. Change the token it passes to `APIClient` so the session token wins when present:

```swift
    func makeClient() -> APIClient? {
        guard let url = URL(string: apiBaseURL), !userId.isEmpty else { return nil }
        let bearer = sessionToken ?? apiToken
        guard !bearer.isEmpty else { return nil }
        return APIClient(baseURL: url, token: bearer, userId: userId)
    }
```
(Adapt to the existing `makeClient()` shape — the essential change is `let bearer = sessionToken ?? apiToken` and using `bearer` as the `token:` argument. Keep the existing `isConfigured` logic; add `isSignedIn` as an alternative path to "ready".)

- [ ] **Step 3: Build**

Run the iOS build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit** (blank team → commit → restore team)

```bash
cd ~/readiness-coach
sed -i '' 's/DEVELOPMENT_TEAM = X9G6H8M527;/DEVELOPMENT_TEAM = "";/g' ios/ReadinessCoach.xcodeproj/project.pbxproj
git add ios/ReadinessCoach/Settings/AppSettings.swift ios/ReadinessCoach.xcodeproj/project.pbxproj
git commit -m "feat(auth): AppSettings session token + sign out (iOS)"
sed -i '' 's/DEVELOPMENT_TEAM = "";/DEVELOPMENT_TEAM = X9G6H8M527;/g' ios/ReadinessCoach.xcodeproj/project.pbxproj
```

---

### Task 13: Sign in with Apple flow helper

**Files:**
- Create: `ios/ReadinessCoach/Services/AppleSignIn.swift`

**Interfaces:**
- Produces: `struct AppleCredential { let identityToken: String; let fullName: String? }`; `enum AppleSignIn { static func credential(from authorization: ASAuthorization) -> AppleCredential? }`. Parses an `ASAuthorizationAppleIDCredential` into the identity-token string and a joined full name (available only on first authorization).

- [ ] **Step 1: Implement**

Create `ios/ReadinessCoach/Services/AppleSignIn.swift`:

```swift
import AuthenticationServices
import Foundation

struct AppleCredential {
    let identityToken: String
    let fullName: String?
}

/// Extracts the identity token + first-time name from a Sign in with Apple result.
enum AppleSignIn {
    static func credential(from authorization: ASAuthorization) -> AppleCredential? {
        guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = apple.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else { return nil }

        var name: String?
        if let components = apple.fullName {
            let joined = [components.givenName, components.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            name = joined.isEmpty ? nil : joined
        }
        return AppleCredential(identityToken: token, fullName: name)
    }
}
```

- [ ] **Step 2: Build**

Run the iOS build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit** (blank team → commit → restore team)

```bash
cd ~/readiness-coach
sed -i '' 's/DEVELOPMENT_TEAM = X9G6H8M527;/DEVELOPMENT_TEAM = "";/g' ios/ReadinessCoach.xcodeproj/project.pbxproj
git add ios/ReadinessCoach/Services/AppleSignIn.swift ios/ReadinessCoach.xcodeproj/project.pbxproj
git commit -m "feat(auth): Sign in with Apple credential parsing (iOS)"
sed -i '' 's/DEVELOPMENT_TEAM = "";/DEVELOPMENT_TEAM = X9G6H8M527;/g' ios/ReadinessCoach.xcodeproj/project.pbxproj
```

---

### Task 14: Enable the Sign in with Apple capability

**Files:**
- Modify: `ios/ReadinessCoach/ReadinessCoach.entitlements`
- Modify: `ios/ReadinessCoach.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: the app entitlement `com.apple.developer.applesignin = ["Default"]`, and the `com.apple.developer.applesignin` capability provisioned so `SignInWithAppleButton` works on-device.

- [ ] **Step 1: Add the entitlement key**

In `ios/ReadinessCoach/ReadinessCoach.entitlements`, add inside the top-level `<dict>`:

```xml
	<key>com.apple.developer.applesignin</key>
	<array>
		<string>Default</string>
	</array>
```

- [ ] **Step 2: Register the capability in the project**

In `ios/ReadinessCoach.xcodeproj/project.pbxproj`, find the target's `SystemCapabilities` (under `TargetAttributes`) or add one. Add:

```
com.apple.developer.applesignin = { enabled = 1; };
```
If `TargetAttributes`/`SystemCapabilities` is absent, open the project in Xcode → target → Signing & Capabilities → **+ Capability → Sign in with Apple** (this writes both the entitlement and the capability). Prefer the Xcode UI here — it provisions the App ID capability on the developer account, which a raw pbxproj edit does not.

- [ ] **Step 3: Build**

Run the iOS build command. Expected: `** BUILD SUCCEEDED **` (signing must resolve with the entitlement; the local `DEVELOPMENT_TEAM` is set during the build).

- [ ] **Step 4: Commit** (blank team → commit → restore team)

```bash
cd ~/readiness-coach
sed -i '' 's/DEVELOPMENT_TEAM = X9G6H8M527;/DEVELOPMENT_TEAM = "";/g' ios/ReadinessCoach.xcodeproj/project.pbxproj
git add ios/ReadinessCoach/ReadinessCoach.entitlements ios/ReadinessCoach.xcodeproj/project.pbxproj
git commit -m "feat(auth): enable Sign in with Apple capability (iOS)"
sed -i '' 's/DEVELOPMENT_TEAM = "";/DEVELOPMENT_TEAM = X9G6H8M527;/g' ios/ReadinessCoach.xcodeproj/project.pbxproj
```

---

### Task 15: Redesign onboarding around Sign in with Apple

**Files:**
- Modify: `ios/ReadinessCoach/Views/OnboardingView.swift`

**Interfaces:**
- Consumes: `AppleSignIn` (Task 13), `APIClient.signInWithApple` (Task 11), `AppSettings.applyAuth`/`isSignedIn` (Task 12).

- [ ] **Step 1: Rewrite the view**

Replace the body of `ios/ReadinessCoach/Views/OnboardingView.swift` so the primary path is Sign in with Apple, Health second, and the API fields live under an "Advanced (developer)" disclosure. Key structure:

```swift
import AuthenticationServices
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var sync: SyncService

    @State private var isRequestingHealth = false
    @State private var healthGranted = false
    @State private var error: String?
    @State private var isFinishing = false
    @State private var showAdvanced = false

    private let health = HealthKitService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    SectionCard(title: "1 · Sign in") {
                        if settings.isSignedIn {
                            Label("Signed in with Apple", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            SignInWithAppleButton(.signIn) { request in
                                request.requestedScopes = [.fullName, .email]
                            } onCompletion: { result in
                                Task { await handleSignIn(result) }
                            }
                            .signInWithAppleButtonStyle(.black)
                            .frame(height: 48)
                        }
                        Text("Your data is tied to your Apple ID. No token to copy.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    SectionCard(title: "2 · Allow Health access") {
                        Text("Readiness Coach reads heart rate, resting HR, HRV, sleep, and workouts. It never writes to Health.")
                            .font(.subheadline)
                        Button {
                            Task { await requestHealth() }
                        } label: {
                            HStack {
                                Image(systemName: healthGranted ? "checkmark.circle.fill" : "heart.text.square")
                                Text(healthGranted ? "Health access requested" : "Allow Health access")
                                Spacer()
                                if isRequestingHealth { ProgressView() }
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRequestingHealth || !settings.isSignedIn)
                    }

                    DisclosureGroup("Advanced (developer)", isExpanded: $showAdvanced) {
                        LabeledField(label: "API URL", text: $settings.apiBaseURL, keyboard: .default)
                        LabeledField(label: "API token", text: $settings.apiToken, secure: true)
                        LabeledField(label: "User ID", text: $settings.userId)
                    }
                    .font(.subheadline)

                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }

                    Button {
                        Task { await finish() }
                    } label: {
                        if isFinishing {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Start & sync").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!settings.isSignedIn || isFinishing)
                }
                .padding()
            }
            .navigationTitle("Welcome")
            .onAppear { settings.ensureUserId() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Readiness Coach").font(.largeTitle.bold())
            Text("A strict, evidence-backed readiness advisor. The score locks the decision; the coach only explains it.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func handleSignIn(_ result: Result<ASAuthorization, Error>) async {
        error = nil
        switch result {
        case .success(let authorization):
            guard let credential = AppleSignIn.credential(from: authorization) else {
                error = "Could not read your Apple sign-in."
                return
            }
            guard let client = settings.makeClientForAuth() else {
                error = "API URL is not set."
                return
            }
            do {
                // Claim the existing local user only if a shared token is configured.
                let claimUserId = settings.userId.isEmpty ? nil : settings.userId
                let claimToken = settings.apiToken.isEmpty ? nil : settings.apiToken
                let auth = try await client.signInWithApple(
                    identityToken: credential.identityToken,
                    fullName: credential.fullName,
                    claimUserId: claimUserId,
                    claimToken: claimToken
                )
                settings.applyAuth(auth, displayName: credential.fullName)
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        case .failure(let err):
            // User cancel is not an error worth showing.
            if (err as? ASAuthorizationError)?.code != .canceled {
                error = err.localizedDescription
            }
        }
    }

    private func requestHealth() async {
        isRequestingHealth = true
        error = nil
        defer { isRequestingHealth = false }
        do {
            try await health.requestAuthorization()
            healthGranted = true
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func finish() async {
        guard settings.isSignedIn else { return }
        isFinishing = true
        defer { isFinishing = false }
        await sync.syncNow(settings)
        if sync.errorMessage == nil {
            settings.hasCompletedOnboarding = true
        } else {
            error = sync.errorMessage
        }
    }
}
```

- [ ] **Step 2: Add a URL-only client builder to `AppSettings`**

The sign-in POST needs the base URL but not a bearer. In `ios/ReadinessCoach/Settings/AppSettings.swift` add:

```swift
    /// A client for the unauthenticated auth endpoint (no bearer needed).
    func makeClientForAuth() -> APIClient? {
        guard let url = URL(string: apiBaseURL) else { return nil }
        return APIClient(baseURL: url, token: "", userId: userId)
    }
```

- [ ] **Step 3: Build**

Run the iOS build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit** (blank team → commit → restore team)

```bash
cd ~/readiness-coach
sed -i '' 's/DEVELOPMENT_TEAM = X9G6H8M527;/DEVELOPMENT_TEAM = "";/g' ios/ReadinessCoach.xcodeproj/project.pbxproj
git add ios/ReadinessCoach/Views/OnboardingView.swift ios/ReadinessCoach/Settings/AppSettings.swift ios/ReadinessCoach.xcodeproj/project.pbxproj
git commit -m "feat(auth): Sign in with Apple onboarding (iOS)"
sed -i '' 's/DEVELOPMENT_TEAM = "";/DEVELOPMENT_TEAM = X9G6H8M527;/g' ios/ReadinessCoach.xcodeproj/project.pbxproj
```

---

### Task 16: Settings Account section + 401 sign-out handling

**Files:**
- Modify: `ios/ReadinessCoach/Views/SettingsView.swift`
- Modify: `ios/ReadinessCoach/Networking/APIClient.swift` (surface 401 clearly — already modeled as `APIError.http(status: 401, ...)`)
- Modify: `ios/ReadinessCoach/Services/SyncService.swift` (on a 401, call `settings.signOut()`)

**Interfaces:**
- Consumes: `AppSettings.signOut`/`appleDisplayName`/`isSignedIn` (Task 12).

- [ ] **Step 1: Add an Account section to Settings**

In `ios/ReadinessCoach/Views/SettingsView.swift`, add near the top of the form (above the existing API fields, which move under a disclosure):

```swift
                Section("Account") {
                    if settings.isSignedIn {
                        LabeledContent("Signed in", value: settings.appleDisplayName ?? "Apple ID")
                        Button("Sign out", role: .destructive) { settings.signOut() }
                    } else {
                        Text("Not signed in").foregroundStyle(.secondary)
                    }
                }
```

Wrap the existing API URL / token / User ID / Test-connection controls in a `DisclosureGroup("Advanced (developer)") { ... }` so they stay available but out of the way.

- [ ] **Step 2: Sign out on a 401**

In `ios/ReadinessCoach/Services/SyncService.swift`, where API errors are caught and turned into `errorMessage`, add a branch: if the error is `APIError.http(status: 401, _)` and `settings.isSignedIn`, call `settings.signOut()` so the app returns to the sign-in screen. Concretely, in the catch block that sets `errorMessage`:

```swift
        if case APIError.http(status: 401, _) = error, settings.isSignedIn {
            settings.signOut()
        }
```
(Place this before assigning `errorMessage`; adapt to the file's existing error-handling shape.)

- [ ] **Step 3: Build**

Run the iOS build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit** (blank team → commit → restore team)

```bash
cd ~/readiness-coach
sed -i '' 's/DEVELOPMENT_TEAM = X9G6H8M527;/DEVELOPMENT_TEAM = "";/g' ios/ReadinessCoach.xcodeproj/project.pbxproj
git add ios/ReadinessCoach/Views/SettingsView.swift ios/ReadinessCoach/Networking/APIClient.swift ios/ReadinessCoach/Services/SyncService.swift ios/ReadinessCoach.xcodeproj/project.pbxproj
git commit -m "feat(auth): Settings account + sign out on 401 (iOS)"
sed -i '' 's/DEVELOPMENT_TEAM = "";/DEVELOPMENT_TEAM = X9G6H8M527;/g' ios/ReadinessCoach.xcodeproj/project.pbxproj
```

---

## Deployment & manual verification (after all tasks)

1. Set `SESSION_SECRET` (random ≥32 chars) and `APPLE_BUNDLE_ID` (the app's bundle id — read it with:
   `grep -m1 PRODUCT_BUNDLE_IDENTIFIER ios/ReadinessCoach.xcodeproj/project.pbxproj`) in Render's environment.
2. Deploy the backend (manual deploy — auto-deploy is off). The currently-shipped app keeps working via dual-mode.
3. Rebuild the app to your device. Tap **Sign in with Apple** → your existing `userId`/token are sent as the claim → backend links your Apple ID to your history → the app switches to the session token.
4. Confirm data still loads (your history is intact), then verify Settings shows "Signed in" and Sign out returns to the sign-in screen.

## Self-Review notes

- **Spec coverage:** schema (T1), env (T2), session JWT + 60d (T3), Apple verification incl. iss/aud/exp (T4), claim/create rule (T5/T6), `/v1/auth/apple` (T7), dual-mode `requireSession` + `req.userId` (T8/T9), Keychain (T10), APIClient + DTOs (T11), settings/session/sign-out (T12/T16), Apple flow (T13), capability (T14), onboarding redesign (T15), Settings account (T16), migration/deploy steps (final section). All spec sections mapped.
- **Type consistency:** `resolveUser(identity, displayName, claim, apiToken, deps)`, `AppleIdentity { sub, email? }`, `AuthResponse { sessionToken, userId }`, `req.userId` are used identically across tasks.
