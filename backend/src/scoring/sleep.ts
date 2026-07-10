import type { PillarScore, SleepInput } from "./types.js";

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

  const drivers: string[] = [];
  if (durationRatio < 0.9) {
    drivers.push(
      `Sleep ${input.durationHours.toFixed(1)}h vs need ${input.needHours}h`,
    );
  }
  if (input.sleepDebtHours >= 1) {
    drivers.push(`Sleep debt ${input.sleepDebtHours.toFixed(1)}h`);
  }
  if (input.consistencyStdHours >= 1) {
    drivers.push("Inconsistent sleep timing/duration");
  }
  if (drivers.length === 0) drivers.push("Sleep on target");

  return { score: Math.round(clamp(raw)), drivers };
}
