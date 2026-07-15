export type Decision = "push" | "maintain" | "recover";

export interface Pillar {
  score: number;
  drivers: { text: string; detail?: string }[];
}

export interface AdvisorNote {
  decision: Decision;
  why: string[];
  prescription: string;
  ifIgnored: string;
  source: "llm" | "template";
}

export interface TodayResponse {
  date: string;
  readiness: number;
  decision: Decision;
  calibrating: boolean;
  pillars: {
    sleep: Pillar;
    recovery: Pillar;
    load: Pillar;
  };
  overridesApplied: string[];
  confidence: "high" | "low";
  missing: string[];
  advisor: AdvisorNote;
  /** Present when a future API version exposes user sync metadata. */
  lastSyncAt?: string;
}

const apiUrl = import.meta.env.VITE_API_URL?.replace(/\/$/, "");
const apiToken = import.meta.env.VITE_API_TOKEN;
const userId = import.meta.env.VITE_USER_ID;

function configurationError(): Error | undefined {
  const missing = [
    !apiUrl && "VITE_API_URL",
    !apiToken && "VITE_API_TOKEN",
    !userId && "VITE_USER_ID",
  ].filter(Boolean);
  return missing.length > 0
    ? new Error(`Missing dashboard configuration: ${missing.join(", ")}. Add it to .env.local.`)
    : undefined;
}

export async function fetchToday(signal?: AbortSignal): Promise<TodayResponse> {
  const configurationIssue = configurationError();
  if (configurationIssue) throw configurationIssue;

  const response = await fetch(`${apiUrl}/v1/today?userId=${encodeURIComponent(userId)}`, {
    signal,
    headers: { Authorization: `Bearer ${apiToken}` },
  });

  if (!response.ok) {
    const detail = await response.json().catch(() => undefined) as { error?: string } | undefined;
    throw new Error(detail?.error ? `Today request failed: ${detail.error}` : `Today request failed (${response.status}).`);
  }

  return response.json() as Promise<TodayResponse>;
}
