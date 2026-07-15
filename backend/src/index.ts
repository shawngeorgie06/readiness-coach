import { createApp } from "./app.js";
import { prisma } from "./db.js";
import { loadEnv } from "./env.js";
import { createGracefulShutdown } from "./shutdown.js";

const env = loadEnv();
const app = createApp({ apiToken: env.API_TOKEN, corsOrigin: env.CORS_ORIGIN });
// Bind all interfaces so a physical iPhone on the same LAN can reach the API
// (localhost-only would only work from the Simulator on this Mac).
const HOST = process.env.HOST ?? "0.0.0.0";
const server = app.listen(env.PORT, HOST, () => {
  console.log(`readiness-coach API on http://${HOST}:${env.PORT}`);
  console.log("Physical iPhone: enter this Mac’s LAN IP in the app (e.g. http://192.168.x.x:%d) — not localhost.", env.PORT);
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
