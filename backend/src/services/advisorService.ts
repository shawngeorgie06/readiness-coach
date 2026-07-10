import { z } from "zod";
import { prisma } from "../db.js";
import type { PillarScore } from "../scoring/types.js";
import { createOpenAiCompatibleClient, type LlmClient } from "./llmClient.js";

export type Decision = "push" | "maintain" | "recover";

export interface AdvisorNoteBody {
  decision: Decision;
  why: string[];
  prescription: string;
  ifIgnored: string;
}

export interface AdvisorNote extends AdvisorNoteBody {
  source: "llm" | "template";
}

export interface AdvisorContext {
  decision: Decision;
  pillars: {
    sleep: PillarScore;
    recovery: PillarScore;
    load: PillarScore;
  };
  overridesApplied: string[];
  missing: string[];
}

const decisionSchema = z.enum(["push", "maintain", "recover"]);
const noteSchema = z.object({
  decision: decisionSchema,
  why: z.array(z.string().trim().min(1)).min(1).max(4),
  prescription: z.string().trim().min(1),
  ifIgnored: z.string().trim().min(1),
});

const RANK: Record<Decision, number> = { push: 2, maintain: 1, recover: 0 };

/** A model may be more cautious, but it can never make the locked score decision more aggressive. */
export function enforceDecisionLock(locked: Decision, body: AdvisorNoteBody): AdvisorNoteBody {
  return {
    ...body,
    decision: RANK[body.decision] > RANK[locked] ? locked : body.decision,
  };
}

export function buildTemplateNote(input: { decision: Decision; drivers: string[] }): AdvisorNoteBody {
  const why = input.drivers.filter((driver) => driver.trim() !== "").slice(0, 4);
  if (why.length === 0) why.push("Current data is incomplete; the recommendation remains conservative.");

  const prescription = input.decision === "push"
    ? "Hard session allowed. Keep form quality high; stop if performance falls off a cliff."
    : input.decision === "maintain"
      ? "Train, but cap intensity (RPE <=7). No PR attempts. Prefer a moderate lift or Zone 2."
      : "Recover. Walk, mobility, or full rest. Do not stack another hard session.";
  const ifIgnored = input.decision === "recover"
    ? "Ignore this and you will dig a deeper hole into the next 48 hours."
    : input.decision === "maintain"
      ? "Ignore this and you risk turning a maintain day into forced recovery tomorrow."
      : "Ignore recovery signals later in the week if you blow past technique for ego PRs.";

  return { decision: input.decision, why, prescription, ifIgnored };
}

function allDrivers(today: AdvisorContext): string[] {
  return [
    ...today.pillars.sleep.drivers,
    ...today.pillars.recovery.drivers,
    ...today.pillars.load.drivers,
    ...today.overridesApplied,
    ...today.missing.map((name) => `Missing ${name} data`),
  ];
}

function metricSummary(today: AdvisorContext) {
  return {
    decision: today.decision,
    pillars: Object.fromEntries(
      Object.entries(today.pillars).map(([name, pillar]) => [name, { score: pillar.score, drivers: pillar.drivers }]),
    ),
    overridesApplied: today.overridesApplied,
    missing: today.missing,
  };
}

function configuredLlm(): LlmClient | undefined {
  const apiKey = process.env.LLM_API_KEY?.trim();
  if (!apiKey) return undefined;
  return createOpenAiCompatibleClient({
    apiKey,
    baseUrl: process.env.LLM_BASE_URL,
    model: process.env.LLM_MODEL,
  });
}

const ADVISOR_SYSTEM_PROMPT = [
  "You are a strict readiness advisor for recomp/general fitness.",
  "Use only the supplied metrics. No diagnosis, cheerleading, or invented data.",
  "The deterministic decision is locked: you may be more conservative but never more aggressive.",
  "Return JSON only with decision, why (2-4 evidence-backed strings), prescription, and ifIgnored.",
].join(" ");

/** Generate a structured note, returning the deterministic template whenever cloud generation is unavailable or invalid. */
export async function generateAdvisorNote(today: AdvisorContext, llm: LlmClient | undefined = configuredLlm()): Promise<AdvisorNote> {
  const fallback = buildTemplateNote({ decision: today.decision, drivers: allDrivers(today) });
  if (llm == null) return { ...fallback, source: "template" };

  try {
    const content = await llm.chat({
      messages: [
        { role: "system", content: ADVISOR_SYSTEM_PROMPT },
        { role: "user", content: JSON.stringify(metricSummary(today)) },
      ],
    });
    const parsed = noteSchema.safeParse(JSON.parse(content));
    if (!parsed.success) return { ...fallback, source: "template" };
    return { ...enforceDecisionLock(today.decision, parsed.data), source: "llm" };
  } catch {
    return { ...fallback, source: "template" };
  }
}

function parseStoredNote(value: unknown): AdvisorNoteBody | undefined {
  const parsed = noteSchema.safeParse(value);
  return parsed.success ? parsed.data : undefined;
}

/** Fetch a once-per-day advisor note, retaining the hard lock if the daily score changes after a sync. */
export async function getAdvisorNote(userId: string, date: Date, today: AdvisorContext): Promise<AdvisorNote> {
  const existing = await prisma.advisorNote.findUnique({ where: { userId_date: { userId, date } } });
  const stored = existing == null ? undefined : parseStoredNote(existing.noteJson);
  if (stored != null && existing?.decision === today.decision) {
    return { ...enforceDecisionLock(today.decision, stored), source: existing.source === "llm" ? "llm" : "template" };
  }

  // Do not make an extra cloud call when a previously generated note becomes stale; a deterministic note is safer.
  const generated = existing == null
    ? await generateAdvisorNote(today)
    : { ...buildTemplateNote({ decision: today.decision, drivers: allDrivers(today) }), source: "template" as const };
  const { source, ...noteJson } = generated;
  await prisma.advisorNote.upsert({
    where: { userId_date: { userId, date } },
    // Store the deterministic decision separately from a note that may choose to be more conservative.
    create: { userId, date, decision: today.decision, noteJson, source },
    update: { decision: today.decision, noteJson, source },
  });
  return generated;
}

export class CoachUnavailableError extends Error {
  constructor() {
    super("Coach is unavailable because cloud advice could not be generated.");
  }
}

function answerViolatesLock(locked: Decision, answer: string): boolean {
  const text = answer.toLowerCase();
  if (locked === "recover") return /\b(pr|personal record|hard|push|max(?:imal)?|all.out|hiit|sprint)\b/.test(text);
  if (locked === "maintain") return /\b(pr|personal record|max(?:imal)?|all.out|hard session)\b/.test(text);
  return false;
}

/** Add an explicit correction if a cloud answer tries to exceed the deterministic training constraint. */
export function enforceAnswerDecisionLock(locked: Decision, answer: string): string {
  if (!answerViolatesLock(locked, answer)) return answer;
  const directive = locked === "recover"
    ? "Locked decision: RECOVER. Do not train hard today; walk, mobility, or full rest only."
    : "Locked decision: MAINTAIN. No PRs or maximal work; cap intensity at RPE 7.";
  return `${answer.trim()}\n\n${directive}`;
}

export async function askCoach(question: string, today: AdvisorContext, llm: LlmClient | undefined = configuredLlm()): Promise<string> {
  if (llm == null) throw new CoachUnavailableError();
  try {
    const answer = await llm.chat({
      messages: [
        {
          role: "system",
          content: `${ADVISOR_SYSTEM_PROMPT} Answer the question directly in plain text. State and obey the locked decision.`,
        },
        { role: "user", content: JSON.stringify({ question, today: metricSummary(today) }) },
      ],
    });
    if (!answer.trim()) throw new Error("Empty coach response");
    return enforceAnswerDecisionLock(today.decision, answer);
  } catch (error) {
    if (error instanceof CoachUnavailableError) throw error;
    throw new CoachUnavailableError();
  }
}
