import { createApp } from "./app.js";
import { loadEnv } from "./env.js";

const env = loadEnv();
const app = createApp({ apiToken: env.API_TOKEN });

const server = app.listen(env.PORT, () => {
  console.log(`readiness-coach API on :${env.PORT}`);
});

export { app, server };
