import { spawnSync } from "node:child_process";
import { requireSafeTestDatabaseUrl } from "../tests/helpers/testDatabase.js";

const testDatabaseUrl = requireSafeTestDatabaseUrl(
  process.env.TEST_DATABASE_URL,
);
const npx = process.platform === "win32" ? "npx.cmd" : "npx";
const env: NodeJS.ProcessEnv = {
  ...process.env,
  NODE_ENV: "test",
  DATABASE_URL: testDatabaseUrl,
  API_TOKEN: process.env.API_TOKEN ?? "integration-test-token",
  LLM_API_KEY: "",
  LLM_BASE_URL: process.env.LLM_BASE_URL ?? "https://api.openai.com/v1",
  LLM_MODEL: process.env.LLM_MODEL ?? "gpt-4o-mini",
};

function run(args: string[]): void {
  const result = spawnSync(npx, args, {
    cwd: process.cwd(),
    env,
    stdio: "inherit",
    shell: process.platform === "win32",
  });

  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

run(["prisma", "migrate", "deploy"]);
run(["vitest", "run", "--config", "vitest.integration.config.ts"]);
