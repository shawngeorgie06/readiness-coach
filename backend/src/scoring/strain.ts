export interface WorkoutStrainInput {
  durationMin: number;
  avgHrBpm: number;
  restingHrBpm: number;
  maxHrBpm: number;
}

/** Deterministic 0–21-ish strain proxy (Whoop-like scale, not identical). */
export function estimateWorkoutStrain(input: WorkoutStrainInput): number {
  if (input.durationMin <= 0 || input.avgHrBpm <= 0) return 0;
  const reserve = Math.max(input.maxHrBpm - input.restingHrBpm, 1);
  const intensity = Math.max(
    0,
    Math.min(1, (input.avgHrBpm - input.restingHrBpm) / reserve)
  );
  const raw = (input.durationMin / 60) * (1 + intensity * 4) * 6;
  return Math.round(Math.min(21, raw) * 10) / 10;
}
