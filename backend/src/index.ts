import { createApp } from "./app.js";
import { prisma } from "./db.js";
import { loadEnv } from "./env.js";
import { resolveKeepAliveUrl, startKeepAlive } from "./keepAlive.js";
import { createGracefulShutdown } from "./shutdown.js";

const env = loadEnv();
const app = createApp({
  apiToken: env.API_TOKEN,
  apiTokenUserId: env.API_TOKEN_USER_ID,
  sessionSecret: env.SESSION_SECRET,
  appleBundleId: env.APPLE_BUNDLE_ID,
  corsOrigin: env.CORS_ORIGIN,
});
const server = app.listen(env.PORT, () => {
  console.log(`readiness-coach API on :${env.PORT}`);
});

const keepAliveUrl = resolveKeepAliveUrl();
const keepAlive = keepAliveUrl
  ? startKeepAlive({ url: keepAliveUrl })
  : undefined;
if (keepAliveUrl) {
  console.log(`keep-alive enabled → ${keepAliveUrl}`);
}

const shutdown = createGracefulShutdown({
  closeServer: () =>
    new Promise<void>((resolve, reject) => {
      keepAlive?.stop();
      server.close((error) => {
        if (error) reject(error);
        else resolve();
      });
    }),
  disconnectDatabase: () => prisma.$disconnect(),
  onError: (error) => {
    console.error("Graceful shutdown failed", error);
  },
});

function handleSignal(): void {
  void shutdown().catch(() => {
    process.exitCode = 1;
  });
}

process.once("SIGINT", handleSignal);
process.once("SIGTERM", handleSignal);

export { app, server };
