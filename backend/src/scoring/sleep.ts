import type { Driver, PillarScore, SleepInput } from "./types.js";

function clamp(n: number, min = 0, max = 100): number {
  return Math.max(min, Math.min(max, n));
}

export function scoreSleep(input: SleepInput): PillarScore {
  const durationRatio = input.durationHours / Math.max(input.needHours, 0.1);
  const durationScore = clamp(durationRatio * 100);

  const restorativeTarget = Math.max(input.needHours * 0.35, 0.1);
  const restorativeScore = clamp(
    (input.restorativeHours / restorativeTarget) * 100,
  );

  const debtPenalty = clamp(input.sleepDebtHours * 12, 0, 50);
  const consistencyPenalty = clamp(input.consistencyStdHours * 15, 0, 25);
  const severeShortfallPenalty = clamp((0.75 - durationRatio) * 70, 0, 30);

  const raw =
    durationScore * 0.45 +
    restorativeScore * 0.25 +
    (100 - debtPenalty) * 0.2 +
    (100 - consistencyPenalty) * 0.1 -
    severeShortfallPenalty;

  const drivers: Driver[] = [];
  if (durationRatio < 0.9) {
    drivers.push({
      text: `${input.durationHours.toFixed(1)}h sleep · below your ${input.needHours}h target`,
      detail: `You slept ${input.durationHours.toFixed(1)}h against your ${input.needHours}h nightly target.`,
    });
  }
  if (input.sleepDebtHours >= 1) {
    drivers.push({
      text: `${input.sleepDebtHours.toFixed(0)}h catch-up owed this week`,
      detail: `Total shortfall against your ${input.needHours}h nightly need across the last 7 nights.`,
    });
  }
  if (input.consistencyStdHours >= 1) {
    drivers.push({
      text: "Irregular sleep schedule",
      detail: `Your nightly sleep length swung about ${input.consistencyStdHours.toFixed(1)}h night-to-night this week; steadier timing improves recovery.`,
    });
  }
  if (drivers.length === 0) {
    drivers.push({ text: "Sleep on target", detail: "Duration, quality, and consistency all look good." });
  }

  return { score: Math.round(clamp(raw)), drivers };
}
