import { describe, expect, it } from "vitest";
import {
  countConsecutiveHighStrain,
  parseRequestedDate,
  sleepWindowForDate,
  summarizeSleep,
} from "../../src/services/todayService.js";

// Sleep-window anchoring is timezone-sensitive; pin the zone so the assertions
// deterministically distinguish local-noon from the old UTC-noon behavior.
process.env.TZ = "America/New_York";

describe("today aggregation helpers", () => {
  it("anchors the sleep window on local noon, not UTC noon", () => {
    const { start, end } = sleepWindowForDate(new Date("2026-07-12T00:00:00.000Z"));
    // Last night = local noon Jul 11 → local noon Jul 12 (a natural night boundary in the user's zone).
    expect(end.getHours()).toBe(12);
    expect(end.getDate()).toBe(12);
    expect(start.getHours()).toBe(12);
    expect(start.getDate()).toBe(11);
    expect(end.getTime() - start.getTime()).toBe(24 * 60 * 60 * 1000);
    // In America/New_York (EDT, −4) local noon is 16:00 UTC — proving it is NOT the old UTC noon (12:00 UTC).
    expect(end.getUTCHours()).toBe(16);
  });


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
