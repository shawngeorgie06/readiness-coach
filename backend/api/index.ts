// Vercel serverless entrypoint. Unlike src/index.ts (long-running server), this
// exports the Express app as a request handler — Vercel owns the listener.
// No keep-alive here: functions are invoked on demand, nothing to keep warm.
import { createApp } from "../src/app.js";
import { loadEnv } from "../src/env.js";

const env = loadEnv();

export default createApp({
  apiToken: env.API_TOKEN,
  apiTokenUserId: env.API_TOKEN_USER_ID,
  sessionSecret: env.SESSION_SECRET,
  appleBundleId: env.APPLE_BUNDLE_ID,
  corsOrigin: env.CORS_ORIGIN,
});
