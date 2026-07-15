import type { Driver, PillarScore, RecoveryInput } from "./types.js";

function clamp(n: number, min = 0, max = 100): number {
  return Math.max(min, Math.min(max, n));
}

export function scoreRecovery(input: RecoveryInput): PillarScore {
  const hrvDelta =
    (input.hrvMs - input.hrvBaseline30dMs) /
    Math.max(input.hrvBaseline30dMs, 1);
  // +20% HRV → ~100, -20% → ~0 on this component
  const hrvScore = clamp(50 + hrvDelta * 250);

  const rhrDelta =
    (input.restingHrBpm - input.restingHrBaseline30dBpm) /
    Math.max(input.restingHrBaseline30dBpm, 1);
  // Elevated RHR hurts.
  const rhrScore = clamp(50 - rhrDelta * 400);

  // Unknown optional data should not reduce an otherwise favorable recovery score.
  let overnightScore = 100;
  if (input.overnightHrBpm != null) {
    const overnightDelta =
      (input.overnightHrBpm - input.restingHrBaseline30dBpm) /
      Math.max(input.restingHrBaseline30dBpm, 1);
    overnightScore = clamp(60 - overnightDelta * 300);
  }

  const raw = hrvScore * 0.55 + rhrScore * 0.3 + overnightScore * 0.15;
  const drivers: Driver[] = [];
  const hrvPct = hrvDelta * 100;
  const hrvQualifier =
    hrvDelta >= 0.05 ? "above your normal" : hrvDelta <= -0.05 ? "below your normal" : "normal for you";
  drivers.push({
    text: `HRV ${input.hrvMs.toFixed(0)}ms · ${hrvQualifier}`,
    detail: `Heart-rate variability is ${input.hrvMs.toFixed(0)}ms vs your 30-day average of ${input.hrvBaseline30dMs.toFixed(0)}ms (${hrvPct >= 0 ? "+" : ""}${hrvPct.toFixed(0)}%). Higher usually means more recovered.`,
  });
  if (rhrDelta > 0.03) {
    drivers.push({
      text: `Resting pulse ${input.restingHrBpm.toFixed(0)} · elevated`,
      detail: `Resting heart rate ${input.restingHrBpm.toFixed(0)} bpm is above your ${input.restingHrBaseline30dBpm.toFixed(0)} bpm baseline — often a sign of fatigue or oncoming illness.`,
    });
  }
  if (hrvDelta >= 0 && rhrDelta <= 0) {
    drivers.push({ text: "Recovery steady", detail: "HRV and resting pulse are both in your normal range." });
  }

  return { score: Math.round(clamp(raw)), drivers };
}
