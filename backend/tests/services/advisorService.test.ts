import { describe, expect, it } from "vitest";
import {
  buildTemplateNote,
  enforceAnswerDecisionLock,
  enforceDecisionLock,
  generateAdvisorNote,
  type AdvisorNoteBody,
} from "../../src/services/advisorService.js";

describe("enforceDecisionLock", () => {
  it("keeps recover even if model text says push", () => {
    const body: AdvisorNoteBody = {
      decision: "push",
      why: ["made up"],
      prescription: "PR day",
      ifIgnored: "whatever",
    };

    expect(enforceDecisionLock("recover", body).decision).toBe("recover");
  });

  it("permits a more conservative model decision", () => {
    const body: AdvisorNoteBody = {
      decision: "recover",
      why: ["conservative"],
      prescription: "Rest",
      ifIgnored: "Fatigue",
    };

    expect(enforceDecisionLock("maintain", body).decision).toBe("recover");
  });
});

describe("buildTemplateNote", () => {
  it("returns strict structure without an LLM", () => {
    const note = buildTemplateNote({
      decision: "maintain",
      drivers: ["HRV -12% vs baseline", "Sleep debt 1.6h"],
    });

    expect(note.decision).toBe("maintain");
    expect(note.why.length).toBeGreaterThan(0);
    expect(note.prescription.length).toBeGreaterThan(0);
  });

  it("uses a conservative fallback when no LLM client is configured", async () => {
    // Force the no-LLM path regardless of any ambient LLM_API_KEY in the env.
    const previousKey = process.env.LLM_API_KEY;
    delete process.env.LLM_API_KEY;
    try {
      const note = await generateAdvisorNote({
        decision: "recover",
        pillars: {
          sleep: { score: 20, drivers: [{ text: "Sleep 4.5h vs need 8h" }] },
          recovery: { score: 30, drivers: [{ text: "HRV -25% vs 30d baseline" }] },
          load: { score: 40, drivers: [{ text: "Yesterday strain 15.0" }] },
        },
        overridesApplied: ["Sleep below 5h"],
        missing: [],
      });

      expect(note.source).toBe("template");
      expect(note.decision).toBe("recover");
    } finally {
      if (previousKey === undefined) delete process.env.LLM_API_KEY;
      else process.env.LLM_API_KEY = previousKey;
    }
  });
});

describe("enforceAnswerDecisionLock", () => {
  it("adds a server-side correction to hard-session advice on a recover day", () => {
    const answer = enforceAnswerDecisionLock("recover", "Go for a hard PR session today.");

    expect(answer).toContain("Locked decision: RECOVER");
  });
});
