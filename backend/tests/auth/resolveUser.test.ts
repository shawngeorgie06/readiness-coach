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
