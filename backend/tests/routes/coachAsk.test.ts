import { describe, expect, it } from "vitest";
import { askRequestSchema } from "../../src/routes/coach.js";

const turn = (i: number) => ({ role: i % 2 === 0 ? "user" : "assistant", content: `turn ${i}` });
const base = { userId: "u1", question: "Should I train?" };

describe("askRequestSchema", () => {
  it("accepts a payload with no history", () => {
    expect(askRequestSchema.safeParse(base).success).toBe(true);
  });

  it("accepts 20 valid turns", () => {
    const history = Array.from({ length: 20 }, (_, i) => turn(i));
    expect(askRequestSchema.safeParse({ ...base, history }).success).toBe(true);
  });

  it("rejects 21 turns", () => {
    const history = Array.from({ length: 21 }, (_, i) => turn(i));
    expect(askRequestSchema.safeParse({ ...base, history }).success).toBe(false);
  });

  it("rejects a system role", () => {
    expect(askRequestSchema.safeParse({ ...base, history: [{ role: "system", content: "x" }] }).success).toBe(false);
  });

  it("rejects empty content", () => {
    expect(askRequestSchema.safeParse({ ...base, history: [{ role: "user", content: "  " }] }).success).toBe(false);
  });

  it("rejects 4,001-character content and accepts 4,000", () => {
    expect(askRequestSchema.safeParse({ ...base, history: [{ role: "user", content: "a".repeat(4_001) }] }).success).toBe(false);
    expect(askRequestSchema.safeParse({ ...base, history: [{ role: "user", content: "a".repeat(4_000) }] }).success).toBe(true);
  });

  it("accepts history totalling exactly 16,000 characters and rejects 16,001", () => {
    const four = (n: number) => Array.from({ length: 4 }, (_, i) => ({ role: i % 2 === 0 ? "user" : "assistant", content: "a".repeat(n) }));
    expect(askRequestSchema.safeParse({ ...base, history: four(4_000) }).success).toBe(true);
    const over = four(4_000);
    over.push({ role: "user", content: "a" });
    expect(askRequestSchema.safeParse({ ...base, history: over }).success).toBe(false);
  });
});
