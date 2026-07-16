import { describe, expect, it } from "vitest";
import {
  countConsecutiveHighStrain,
  parseRequestedDate,
  sleepBounds,
  sleepWindowForDate,
  summarizeSleep,
} from "../../src/services/todayService.js";

// Sleep-window anchoring is timezone-sensitive; pin the zone so the assertions
// deterministically distinguish local-noon from the old UTC-noon behavior.
process.env.TZ = "America/New_York";

describe("today aggregation helpers", () => {
  it("anchors the sleep window on the user's local noon via the tz offset", () => {
    // EDT (−240): the night for Jul 12 runs local noon Jul 11 → local noon Jul 12,
    // i.e. 16:00 UTC Jul 11 → 16:00 UTC Jul 12. Computed from the offset, so it
    // does not depend on the server's own timezone (Render runs in UTC).
    const edt = sleepWindowForDate(new Date("2026-07-12T00:00:00.000Z"), -240);
    expect(edt.start.toISOString()).toBe("2026-07-11T16:00:00.000Z");
    expect(edt.end.toISOString()).toBe("2026-07-12T16:00:00.000Z");
    expect(edt.end.getTime() - edt.start.getTime()).toBe(24 * 60 * 60 * 1000);

    // With no offset it falls back to plain UTC noon-to-noon (legacy behavior).
    const utc = sleepWindowForDate(new Date("2026-07-12T00:00:00.000Z"));
    expect(utc.end.toISOString()).toBe("2026-07-12T12:00:00.000Z");
  });

  it("keeps a full 7h52 Watch night in one day's bucket instead of leaking ~53m", () => {
    // Regression: an Apple Watch night of 01:00–08:52 EDT on Jul 15
    // (= 05:00–12:52 UTC), 7h52m asleep. The old UTC-noon boundary (12:00 UTC =
    // 08:00 EDT) sliced off the 08:00–08:52 tail into the NEXT day, surfacing a
    // phantom ~53-minute "night" for Jul 16.
    const tz = -240; // EDT
    const samples = [
      {
        startAt: new Date("2026-07-15T05:00:00.000Z"),
        endAt: new Date("2026-07-15T12:52:00.000Z"),
        metadata: { stage: "core" },
      },
    ];
    const jul15 = sleepWindowForDate(new Date("2026-07-15T00:00:00.000Z"), tz);
    const jul16 = sleepWindowForDate(new Date("2026-07-16T00:00:00.000Z"), tz);
    // The whole night lands on Jul 15; Jul 16 sees none of it.
    expect(summarizeSleep(samples, jul15.start, jul15.end).durationHours).toBeCloseTo(7.87, 1);
    expect(summarizeSleep(samples, jul16.start, jul16.end).durationHours).toBe(0);

    // Contrast: the old UTC-noon boundary leaks ~52m of the Jul 15 morning into
    // Jul 16 — reproducing the reported "53 minute" bug.
    const jul16Utc = sleepWindowForDate(new Date("2026-07-16T00:00:00.000Z"), 0);
    expect(summarizeSleep(samples, jul16Utc.start, jul16Utc.end).durationHours).toBeGreaterThan(0.5);
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

  it("uses the full in-bed interval when HealthKit has only a partial staged fragment", () => {
    const start = new Date("2026-07-10T00:00:00.000Z");
    const end = new Date("2026-07-10T07:52:00.000Z");
    const summary = summarizeSleep([
      { startAt: start, endAt: end, metadata: { stage: "inBed" } },
      { startAt: new Date("2026-07-10T06:59:00.000Z"), endAt: end, metadata: { stage: "core" } },
    ], start, end);

    expect(summary).toEqual({ durationHours: 7.87, restorativeHours: 0 });
  });

  it("counts only an unbroken streak of high-strain days", () => {
    expect(countConsecutiveHighStrain([15, 14, 8, 16, 15])).toBe(2);
    expect(countConsecutiveHighStrain([15, 8])).toBe(0);
  });

  it("only accepts real YYYY-MM-DD dates", () => {
    expect(parseRequestedDate("2026-07-10")).toBe("2026-07-10");
    expect(() => parseRequestedDate("2026-02-30")).toThrow("date must be YYYY-MM-DD");
  });

  it("returns the earliest asleep start and latest asleep end in the window", () => {
    const winStart = new Date("2026-07-11T16:00:00.000Z");
    const winEnd = new Date("2026-07-12T16:00:00.000Z");
    const bounds = sleepBounds([
      { startAt: new Date("2026-07-12T04:12:00.000Z"), endAt: new Date("2026-07-12T05:00:00.000Z"), metadata: { stage: "core" } },
      { startAt: new Date("2026-07-12T05:00:00.000Z"), endAt: new Date("2026-07-12T07:20:00.000Z"), metadata: { stage: "rem" } },
      { startAt: new Date("2026-07-12T03:00:00.000Z"), endAt: new Date("2026-07-12T03:30:00.000Z"), metadata: { stage: "inBed" } },
    ], winStart, winEnd);
    expect(bounds.sleepStart).toBe("2026-07-12T04:12:00.000Z");
    expect(bounds.sleepEnd).toBe("2026-07-12T07:20:00.000Z");
  });

  it("clamps sleep bounds to the window edges", () => {
    const winStart = new Date("2026-07-11T16:00:00.000Z");
    const winEnd = new Date("2026-07-12T16:00:00.000Z");
    // A single asleep sample that spills past both edges of the window.
    const bounds = sleepBounds([
      { startAt: new Date("2026-07-11T14:00:00.000Z"), endAt: new Date("2026-07-12T18:00:00.000Z"), metadata: { stage: "core" } },
    ], winStart, winEnd);
    expect(bounds.sleepStart).toBe("2026-07-11T16:00:00.000Z");
    expect(bounds.sleepEnd).toBe("2026-07-12T16:00:00.000Z");
  });

  it("returns nulls when no asleep samples overlap the window", () => {
    const bounds = sleepBounds([], new Date("2026-07-11T16:00:00.000Z"), new Date("2026-07-12T16:00:00.000Z"));
    expect(bounds).toEqual({ sleepStart: null, sleepEnd: null });
  });
});
