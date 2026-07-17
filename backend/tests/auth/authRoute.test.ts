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
