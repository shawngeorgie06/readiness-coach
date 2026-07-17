# Sign in with Apple — Onboarding & Authentication Design

**Date:** 2026-07-16
**Status:** Approved (design), pending implementation plan

## Goal

Replace the manual "paste API URL + bearer token + user ID" onboarding with **Sign in with Apple**, giving the app real per-user accounts and a two-tap, no-typing sign-up. The existing single user's health history must be preserved (claimed) on first sign-in.

## Context: where we are today

- **No account system.** All `/v1` routes are gated by one shared `API_TOKEN` (`requireToken` middleware compares the bearer to `env.API_TOKEN`). The caller passes `userId` separately as a query param / request body; the backend trusts it verbatim.
- **Per-install identity** is a random `userId` (a `User.id`, cuid) generated on the device and saved in settings.
- **Onboarding** (`OnboardingView.swift`) is a developer config form: API URL (pre-filled default), API token (paste — the only real friction), User ID (auto-generated, under "Advanced"), a Test-connection button, then Allow Health, then Start & sync.
- **Prisma `User`** has: `id` (cuid), `createdAt`, `goal`, `sleepNeedHours`, relations, `settings Json?`. No auth fields.

## Decisions (locked)

1. **Auth model:** real multi-user accounts via Sign in with Apple (not a personal-only convenience layer).
2. **Existing data:** **claim** the current user's history on first sign-in — never start fresh for the existing user.
3. **Distribution:** personal for now; build the auth, **skip App Store-specific work** (review prep, Hide-My-Email rigor, etc.). The Sign in with Apple *capability/entitlement* is still enabled in the Xcode project so it works on-device.
4. **Session strategy (Approach A):** the backend issues its **own** session JWT after verifying Apple's identity token. Stateless, no session table.

## Architecture overview

```
iOS: SignInWithAppleButton
      │  identityToken (+ claimUserId/claimToken if device has them)
      ▼
POST /v1/auth/apple  (unauthenticated)
      │  1. verify Apple identity token (jose + Apple JWKS)
      │  2. resolve/claim/create User (by appleSub)
      │  3. mint session JWT { userId }, HS256, 60d
      ▼
  { sessionToken, userId }
      │  stored: sessionToken → Keychain, userId → settings
      ▼
All /v1/* calls: Authorization: Bearer <sessionToken>
      ▼
requireSession middleware → verifies JWT → sets req.userId
```

## Backend design

### 1. Schema change (one additive migration)

Add to `model User` — all nullable, so the migration cannot lose or break existing rows:

```prisma
appleSub    String? @unique   // stable Apple user id (JWT `sub`); null until claimed
email       String?           // captured only on first Apple sign-in
displayName String?           // captured only on first Apple sign-in
```

### 2. Apple identity-token verification

- Add dependency: **`jose`**.
- Create a remote JWKS set from `https://appleid.apple.com/auth/keys` (jose caches it).
- Verify the token with: signature (via JWKS), `issuer === "https://appleid.apple.com"`, `audience === env.APPLE_BUNDLE_ID`, and expiry.
- Extract `sub` (stable Apple user id) and, when present, `email`.
- Expose this behind an interface (`AppleVerifier`) so tests can inject a fake and never hit Apple.

### 3. `POST /v1/auth/apple` (unauthenticated login endpoint)

Request body: `{ identityToken: string, claimUserId?: string, claimToken?: string, email?: string, fullName?: string }`

Logic (the resolvable core is a pure `resolveUser(sub, email, displayName, claim, deps)`):

1. Verify `identityToken` → `sub` (+ email if present). On failure → `401 { error: "invalid_apple_token" }`.
2. Find `User` where `appleSub === sub`.
   - **Found** → that user logs in.
   - **Not found:**
     - **Claim path** — if `claimUserId` and `claimToken` are present **and** `claimToken === env.API_TOKEN` **and** the user `claimUserId` exists **and** that user's `appleSub` is null → set `appleSub = sub` (+ `email`/`displayName` first-time). This links the Apple ID to the existing history. Only a device holding the shared token can do this.
     - **New-user path** — otherwise create a new `User` with `appleSub = sub` (+ email/displayName captured first-time).
3. Mint session JWT: `jose` `SignJWT({ userId: user.id })`, `HS256`, signed with `env.SESSION_SECRET`, `expiresIn: "60d"`.
4. Respond `{ sessionToken, userId }`.

Claim edge cases: wrong/missing `claimToken` → falls through to new-user (does **not** error, does **not** link). Target user already has an `appleSub` → not claimable (falls through to new-user). Apple ID already mapped → step 2 "found" wins before any claim is considered.

### 4. `requireSession` middleware (replaces `requireToken` on `/v1`)

Dual-mode during transition so deploying the backend never breaks the currently-shipped app:

1. Read bearer token.
2. If it verifies as a session JWT (via `SESSION_SECRET`) → set `req.userId = payload.userId`, `next()`.
3. Else if it equals `env.API_TOKEN` → **legacy fallback**: set `req.userId` from `req.query.userId` (or body `userId`), `next()`.
4. Else → `401 { error: "unauthorized" }`.

`/v1/auth/apple` and `/health` are exempt (not behind `requireSession`).

Routes change from reading `req.query.userId` to reading **`req.userId`** (set by the middleware). The session path ignores any client-supplied `userId`, closing the "trust the client's userId" hole for signed-in users.

### 5. Environment variables

- `SESSION_SECRET` — new, random ≥32 bytes; signs/verifies session JWTs.
- `APPLE_BUNDLE_ID` — the iOS app's bundle identifier; the required `aud` of Apple identity tokens.
- `API_TOKEN` — **kept**: authorizes the one-time claim and powers the legacy dual-mode fallback.

## iOS design

### 1. Sign in with Apple flow

- `AuthenticationServices` `SignInWithAppleButton` (SwiftUI). Requested scopes `[.fullName, .email]`.
- On success: read `identityToken` (Data→UTF8 string), the stable `user` id, and first-time `fullName`/`email`.
- POST to `/v1/auth/apple`. If the device still has a saved shared token + userId (the existing user's device), include them as `claimToken`/`claimUserId`.
- Store the returned `sessionToken` in the **Keychain**; store `userId` in settings.

### 2. Session storage & APIClient

- New Keychain-backed store for `sessionToken` (a credential — not UserDefaults).
- `APIClient` sends `Authorization: Bearer <sessionToken>` on all `/v1` calls. The manual token field leaves the normal path.
- `userId` no longer needs to travel as a query param for signed-in users (backend derives it from the session); it may remain for the legacy/advanced path.

### 3. Expiry handling

- On `401` from any `/v1` call: clear the stored session and present the Sign in with Apple screen. One tap + Face ID restores it. (Silent server-side refresh needs the Apple key setup we are deliberately skipping; a ~60-day re-tap is the accepted v1 behavior.)

### 4. Redesigned onboarding (`OnboardingView.swift`)

Normal path — **two taps, no typing:**
1. Welcome (app name + one-line pitch).
2. **Sign in with Apple** — the single primary action.
3. **Allow Health access** (appears after sign-in).
4. Auto-sync → done.

All technical fields (API URL, API token, User ID, Test connection) move into a **collapsed "Advanced (developer)" disclosure** at the bottom for debugging. The default API URL stays pre-filled.

### 5. Settings (`SettingsView.swift`)

- New **Account** section: "Signed in with Apple" + display name/email, and a **Sign out** action (clears the Keychain session → returns to onboarding).
- Existing advanced API fields stay, tucked under a disclosure.

## Migration path (incremental, safe)

1. Ship the **backend** (schema migration + endpoint + dual-mode middleware). The current app keeps working unchanged via the legacy shared-token path.
2. Ship the **iOS** Sign in with Apple build.
3. Existing user taps Sign in with Apple once → device sends claim → history linked to the Apple ID → app switches to session auth.
4. New users: fresh install, no saved shared token → Sign in with Apple → new empty account.

## Testing

### Backend (vitest, matching the existing pure-helper test pattern)

Extract `resolveUser(...)` as a pure function with an injectable `AppleVerifier`; test without network:
- New Apple `sub` with no claim → creates a new user.
- Valid claim (`claimToken === API_TOKEN`, target user exists, `appleSub` null) → links the existing user; no new user created.
- Claim with wrong/missing `claimToken` → new user created; existing user untouched.
- Claim when target user already has an `appleSub` → not linked; new user created.
- Known Apple `sub` (already mapped) → returns the existing user, ignores any claim fields.
- Session JWT round-trip: `mintSession` → `requireSession` extracts the correct `userId`.
- Dual-mode: legacy `API_TOKEN` bearer + `?userId=` still authorizes and sets `req.userId`.

### iOS

- Keychain session store: unit-test store / retrieve / delete.
- App builds for the simulator.
- Live Apple sign-in verified on-device (simulator also supports Sign in with Apple with a test Apple ID).

## Out of scope (this pass)

- App Store submission, review prep, and App Store account-deletion polish (in-app delete already exists).
- Server-side Apple refresh-token flow (requires the Apple private key / Service ID setup).
- Remote session revocation / a session table (Approach B) — revisit only if multi-device logout management is needed.
- Any change to scoring, sync payloads, or health data handling.

## Constraints carried from the project

- Real data only; the deterministic score owns the decision; the app renders the server's decision/readiness verbatim. (Auth work touches none of this.)
- The iOS `DEVELOPMENT_TEAM` signing value stays uncommitted (blank in commits, restored locally).
