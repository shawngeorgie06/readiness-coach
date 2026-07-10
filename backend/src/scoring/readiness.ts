import { scoreLoad } from "./load.js";
import { scoreRecovery } from "./recovery.js";
import { scoreSleep } from "./sleep.js";
import type {
  Decision,
  LoadInput,
  ReadinessResult,
  RecoveryInput,
  SleepInput,
} from "./types.js";

export interface ReadinessInput {
  sleep: SleepInput;
  recovery: RecoveryInput;
  load: LoadInput;
  meta: {
    daysOfHistory: number;
    consecutiveHighStrainDays: number;
  };
}

function decisionFromScore(score: number): Decision {
  if (score >= 75) return "push";
  if (score >= 50) return "maintain";
  return "recover";
}

const DECISION_RANK: Record<Decision, number> = {
  push: 2,
  maintain: 1,
  recover: 0,
};

function moreConservative(a: Decision, b: Decision): Decision {
  return DECISION_RANK[a] <= DECISION_RANK[b] ? a : b;
}

/**
 * Computes a deterministic readiness result. Overrides and calibration can only
 * make the score-derived decision more conservative; they never upgrade it.
 */
export function computeReadiness(input: ReadinessInput): ReadinessResult {
  const sleep = scoreSleep(input.sleep);
  const recovery = scoreRecovery(input.recovery);
  const load = scoreLoad(input.load);

  const readiness = Math.round(
    sleep.score * 0.35 + recovery.score * 0.4 + load.score * 0.25,
  );

  let decision = decisionFromScore(readiness);
  const overridesApplied: string[] = [];

  if (input.sleep.durationHours < 5) {
    decision = moreConservative(decision, "recover");
    overridesApplied.push("sleep_under_5h");
  }

  const hrvDelta =
    (input.recovery.hrvMs - input.recovery.hrvBaseline30dMs) /
    Math.max(input.recovery.hrvBaseline30dMs, 1);
  const rhrElevated =
    input.recovery.restingHrBpm >
    input.recovery.restingHrBaseline30dBpm * 1.03;
  if (hrvDelta <= -0.2 && rhrElevated) {
    decision = moreConservative(decision, "recover");
    overridesApplied.push("hrv_rhr_stress");
  }

  if (input.meta.consecutiveHighStrainDays >= 2) {
    decision = moreConservative(decision, "recover");
    overridesApplied.push("back_to_back_high_strain");
  }

  const calibrating = input.meta.daysOfHistory < 14;
  if (calibrating && decision === "push") {
    decision = "maintain";
    overridesApplied.push("calibrating_cap");
  }

  return {
    sleep,
    recovery,
    load,
    readiness,
    decision,
    overridesApplied,
    calibrating,
  };
}
