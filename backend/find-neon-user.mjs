// Ask Neon which user owns the data. Prints only IDs and counts.
// The connection string is read from stdin, never echoed, never stored.
import { PrismaClient } from "@prisma/client";
import readline from "node:readline";

const url = await new Promise((resolve) => {
  const rl = readline.createInterface({ input: process.stdin, output: process.stderr, terminal: true });
  rl.question("Neon DATABASE_URL: ", (a) => { rl.close(); resolve(a.trim()); });
  rl._writeToOutput = () => {};   // suppress echo
});
process.stderr.write("\n");

const prisma = new PrismaClient({ datasources: { db: { url } } });
try {
  const rows = await prisma.$queryRawUnsafe(`
    SELECT u.id,
           u."createdAt"::date::text          AS created,
           count(DISTINCT s.id)::int          AS samples,
           count(DISTINCT d.id)::int          AS scores,
           max(d."date")::text                AS last_score
    FROM "User" u
    LEFT JOIN "HealthSample" s ON s."userId" = u.id
    LEFT JOIN "DailyScore"  d ON d."userId" = u.id
    GROUP BY u.id, u."createdAt"
    ORDER BY samples DESC;`);
  console.table(rows);
} finally {
  await prisma.$disconnect();
}
