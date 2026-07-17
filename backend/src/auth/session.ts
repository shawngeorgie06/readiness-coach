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
    const { payload } = await jwtVerify(token, key(secret), { algorithms: ["HS256"] });
    return typeof payload.userId === "string" ? payload.userId : null;
  } catch {
    return null;
  }
}
