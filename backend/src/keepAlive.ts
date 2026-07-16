/**
 * Keep a Render free web service from spinning down after 15 minutes of idle.
 * Hits the public /health URL on an interval so Render sees inbound traffic.
 *
 * This only helps while the process is already awake. Pair with an external
 * ping (GitHub Action / cron-job.org) so a cold service can be woken too.
 */
export interface KeepAliveOptions {
  /** Full health URL, e.g. https://my-app.onrender.com/health */
  url: string;
  /** Default 10 minutes — under Render's 15-minute idle spin-down. */
  intervalMs?: number;
  fetchImpl?: typeof fetch;
  log?: (message: string) => void;
  logError?: (message: string, error: unknown) => void;
}

export interface KeepAliveHandle {
  stop: () => void;
}

export function resolveKeepAliveUrl(
  env: NodeJS.ProcessEnv = process.env,
): string | undefined {
  const explicit = env.KEEP_ALIVE_URL?.trim();
  if (explicit) return explicit.replace(/\/$/, "");

  const render = env.RENDER_EXTERNAL_URL?.trim();
  if (render) return `${render.replace(/\/$/, "")}/health`;

  return undefined;
}

export function startKeepAlive({
  url,
  intervalMs = 10 * 60 * 1000,
  fetchImpl = fetch,
  log = console.log,
  logError = console.error,
}: KeepAliveOptions): KeepAliveHandle {
  let stopped = false;

  const ping = async () => {
    if (stopped) return;
    try {
      const res = await fetchImpl(url, { method: "GET" });
      if (!res.ok) {
        logError(`keep-alive ping failed: ${res.status}`, undefined);
        return;
      }
      log(`keep-alive ping ok → ${url}`);
    } catch (error) {
      logError("keep-alive ping error", error);
    }
  };

  // First ping shortly after boot so Render records traffic soon after deploy.
  const initial = setTimeout(() => {
    void ping();
  }, 30_000);

  const timer = setInterval(() => {
    void ping();
  }, intervalMs);

  // Don't keep the process alive solely because of these timers.
  initial.unref?.();
  timer.unref?.();

  return {
    stop: () => {
      stopped = true;
      clearTimeout(initial);
      clearInterval(timer);
    },
  };
}
