import { createApp } from "./app.js";
import { prisma } from "./db.js";
import { loadEnv } from "./env.js";
import { createGracefulShutdown } from "./shutdown.js";

const env = loadEnv();
const app = createApp({ apiToken: env.API_TOKEN, corsOrigin: env.CORS_ORIGIN });
const server = app.listen(env.PORT, () => {
  console.log(`readiness-coach API on :${env.PORT}`);
});

const shutdown = createGracefulShutdown({
  closeServer: () =>
    new Promise<void>((resolve, reject) => {
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
