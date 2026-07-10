import type { PillarScore, RecoveryInput } from "./types.js";

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
  const drivers: string[] = [];
  const hrvPct = hrvDelta * 100;
  drivers.push(
    `HRV ${hrvPct >= 0 ? "+" : ""}${hrvPct.toFixed(0)}% vs 30d baseline`
  );
  if (rhrDelta > 0.03) drivers.push("Resting HR elevated vs baseline");
  if (hrvDelta >= 0 && rhrDelta <= 0) drivers.push("Recovery markers stable");

  return { score: Math.round(clamp(raw)), drivers };
}
