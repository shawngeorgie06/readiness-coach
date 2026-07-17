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
        algorithms: ["RS256"],
      });
      if (typeof payload.sub !== "string" || payload.sub.length === 0) {
        throw new Error("apple identity token missing sub");
      }
      const email = typeof payload.email === "string" ? payload.email : undefined;
      return { sub: payload.sub, email };
    },
  };
}
