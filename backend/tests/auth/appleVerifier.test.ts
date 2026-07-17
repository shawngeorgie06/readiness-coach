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
