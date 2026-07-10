/** Returns the arithmetic mean, or zero when no historical samples exist. */
export function mean(values: number[]): number {
  if (values.length === 0) return 0;
  return values.reduce((total, value) => total + value, 0) / values.length;
}

/** Returns the population standard deviation for a set of historical samples. */
export function stddev(values: number[]): number {
  if (values.length < 2) return 0;

  const average = mean(values);
  const variance = mean(values.map((value) => (value - average) ** 2));
  return Math.sqrt(variance);
}

/** Returns the average of the most recent values within a rolling window. */
export function rollingMean(values: number[], window: number): number {
  return mean(values.slice(-Math.max(0, window)));
}
