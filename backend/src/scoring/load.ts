import type { LoadInput, PillarScore } from "./types.js";

function clamp(n: number, min = 0, max = 100): number {
  return Math.max(min, Math.min(max, n));
}

export function scoreLoad(input: LoadInput): PillarScore {
  // Freshness: lower yesterday strain relative to capacity → higher score.
  const relative =
    input.yesterdayStrain /
    Math.max(input.strain7dAvg || input.yesterdayStrain || 1, 1);
  const freshness = clamp(100 - (relative - 0.6) * 80);

  // ACR: ideal ~0.8–1.3.
  let acrScore = 80;
  if (input.acuteChronicRatio > 1.3) {
    acrScore = clamp(80 - (input.acuteChronicRatio - 1.3) * 100);
  } else if (input.acuteChronicRatio < 0.7) {
    acrScore = clamp(70 - (0.7 - input.acuteChronicRatio) * 40);
  }

  const raw = freshness * 0.55 + acrScore * 0.45;
  const drivers: string[] = [];
  drivers.push(`Yesterday strain ${input.yesterdayStrain.toFixed(1)}`);
  drivers.push(`Acute:chronic ${input.acuteChronicRatio.toFixed(2)}`);
  if (input.acuteChronicRatio > 1.3) {
    drivers.push("Training load spiked vs chronic baseline");
  }

  return { score: Math.round(clamp(raw)), drivers };
}
