const TZ = -240;

const endpoints = [
  "/v1/today",
  "/v1/body?days=30",
  "/v1/sleep?days=7",
  "/v1/sleep?days=30",
  "/v1/sleep?days=90",
  "/v1/train?days=28",
  "/v1/history?days=30",
  "/v1/history?days=90",
];

function arg(name: string, fallback?: string): string {
  const index = process.argv.indexOf(`--${name}`);
  const value = index >= 0 ? process.argv[index + 1] : fallback;
  if (!value) throw new Error(`Missing --${name}`);
  return value;
}

function percentile(sorted: number[], p: number): number {
  const index = Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1);
  return sorted[Math.max(0, index)];
}

async function timedGet(url: string, token: string): Promise<{ ms: number; bytes: number; status: number }> {
  const start = performance.now();
  const response = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  const body = await response.arrayBuffer();
  return { ms: performance.now() - start, bytes: body.byteLength, status: response.status };
}

async function main() {
  const base = arg("base", "http://127.0.0.1:3000").replace(/\/$/, "");
  const token = arg("token");
  const runs = Number(arg("runs", "30"));
  if (!Number.isInteger(runs) || runs < 1) throw new Error("--runs must be a positive integer");

  const rows: string[][] = [["endpoint", "p50 ms", "p95 ms", "bytes"]];
  for (const endpoint of endpoints) {
    const url = `${base}${endpoint}${endpoint.includes("?") ? "&" : "?"}tz=${TZ}`;
    const warm = await timedGet(url, token);
    if (warm.status !== 200) throw new Error(`${endpoint} returned ${warm.status}`);
    const times: number[] = [];
    let bytes = warm.bytes;
    for (let i = 0; i < runs; i += 1) {
      const result = await timedGet(url, token);
      if (result.status !== 200) throw new Error(`${endpoint} returned ${result.status}`);
      times.push(result.ms);
      bytes = result.bytes;
    }
    times.sort((a, b) => a - b);
    rows.push([endpoint, percentile(times, 50).toFixed(1), percentile(times, 95).toFixed(1), String(bytes)]);
  }

  const widths = rows[0].map((_, col) => Math.max(...rows.map((row) => row[col].length)));
  for (const row of rows) {
    console.log(row.map((cell, col) => (col === 0 ? cell.padEnd(widths[col]) : cell.padStart(widths[col]))).join("  "));
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
