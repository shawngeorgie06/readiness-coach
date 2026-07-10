import { describe, expect, it } from "vitest";
import {
  countConsecutiveHighStrain,
  parseRequestedDate,
  summarizeSleep,
} from "../../src/services/todayService.js";

describe("today aggregation helpers", () => {
  it("uses only asleep stages and calculates restorative sleep", () => {
    const start = new Date("2026-07-10T00:00:00.000Z");
    const end = new Date("2026-07-10T08:00:00.000Z");
    const summary = summarizeSleep([
      { startAt: start, endAt: new Date("2026-07-10T03:00:00.000Z"), metadata: { stage: "core" } },
      { startAt: new Date("2026-07-10T03:00:00.000Z"), endAt: new Date("2026-07-10T05:00:00.000Z"), metadata: { stage: "deep" } },
      { startAt: new Date("2026-07-10T05:00:00.000Z"), endAt: end, metadata: { stage: "rem" } },
      { startAt: start, endAt: end, metadata: { stage: "inBed" } },
    ], start, end);

    expect(summary).toEqual({ durationHours: 8, restorativeHours: 5 });
  });

  it("counts only an unbroken streak of high-strain days", () => {
    expect(countConsecutiveHighStrain([15, 14, 8, 16, 15])).toBe(2);
    expect(countConsecutiveHighStrain([15, 8])).toBe(0);
  });

  it("only accepts real YYYY-MM-DD dates", () => {
    expect(parseRequestedDate("2026-07-10")).toBe("2026-07-10");
    expect(() => parseRequestedDate("2026-02-30")).toThrow("date must be YYYY-MM-DD");
  });
});
