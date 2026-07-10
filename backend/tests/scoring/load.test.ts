import { describe, expect, it } from "vitest";
import { scoreLoad } from "../../src/scoring/load.js";

describe("scoreLoad", () => {
  it("scores higher when yesterday strain is moderate vs weekly avg", () => {
    const result = scoreLoad({
      yesterdayStrain: 8,
      strain7dAvg: 9,
      acuteChronicRatio: 1.0,
    });
    expect(result.score).toBeGreaterThanOrEqual(60);
  });

  it("scores lower when acute:chronic is spiked", () => {
    const result = scoreLoad({
      yesterdayStrain: 18,
      strain7dAvg: 10,
      acuteChronicRatio: 1.6,
    });
    expect(result.score).toBeLessThan(55);
  });
});
