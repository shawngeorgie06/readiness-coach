import type { Driver, LoadInput, PillarScore } from "./types.js";

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
  const drivers: Driver[] = [];
  const yStrain = input.yesterdayStrain;
  const strainText =
    yStrain < 4 ? "Rest day yesterday"
      : yStrain < 10 ? `Light day yesterday (strain ${yStrain.toFixed(0)})`
        : `Hard day yesterday (strain ${yStrain.toFixed(0)})`;
  drivers.push({
    text: strainText,
    detail: `Strain rates how hard training was, 0–21. Yesterday was ${yStrain.toFixed(1)}.`,
  });
  const balance =
    input.acuteChronicRatio > 1.3 ? "ramping up" : input.acuteChronicRatio < 0.7 ? "backing off" : "balanced";
  drivers.push({
    text: `Training load ${balance}`,
    detail: `Your last 7 days of training vs your usual 28-day level is ${input.acuteChronicRatio.toFixed(2)}× (0.8–1.3 is the healthy zone).`,
  });
  if (input.acuteChronicRatio > 1.3) {
    drivers.push({
      text: "Training load spiking",
      detail: `The last week is well above your norm (${input.acuteChronicRatio.toFixed(2)}×); injury risk rises above 1.3×.`,
    });
  }

  return { score: Math.round(clamp(raw)), drivers };
}
