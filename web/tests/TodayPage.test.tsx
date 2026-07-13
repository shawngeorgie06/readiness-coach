import { render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import * as api from "../src/api";
import { TodayPage } from "../src/pages/TodayPage";
import type { TodayResponse } from "../src/api";

const baseToday: TodayResponse = {
  date: "2026-07-10",
  readiness: 82,
  decision: "push",
  calibrating: false,
  pillars: {
    sleep: { score: 90, drivers: [{ text: "Full night" }] },
    recovery: { score: 78, drivers: [{ text: "HRV up" }] },
    load: { score: 70, drivers: [{ text: "Moderate week" }] },
  },
  overridesApplied: [],
  confidence: "high",
  missing: [],
  advisor: {
    decision: "push",
    why: ["Great sleep"],
    prescription: "Go hard today.",
    ifIgnored: "Nothing bad happens.",
    source: "template",
  },
};

describe("TodayPage", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("shows a loading state before data arrives", () => {
    vi.spyOn(api, "fetchToday").mockReturnValue(new Promise(() => {}));

    render(<TodayPage />);

    expect(screen.getByText(/Loading today.s readiness/i)).toBeInTheDocument();
  });

  it("renders the readiness score and advisor note once loaded", async () => {
    vi.spyOn(api, "fetchToday").mockResolvedValue(baseToday);

    render(<TodayPage />);

    expect(await screen.findByText("82")).toBeInTheDocument();
    expect(screen.getByText("Go hard today.")).toBeInTheDocument();
    expect(screen.getByText("Great sleep")).toBeInTheDocument();
  });

  it("shows a calibrating notice when the baseline is still forming", async () => {
    vi.spyOn(api, "fetchToday").mockResolvedValue({ ...baseToday, calibrating: true });

    render(<TodayPage />);

    expect(await screen.findByText(/Calibrating/i)).toBeInTheDocument();
  });

  it("shows an error state when the fetch fails", async () => {
    vi.spyOn(api, "fetchToday").mockRejectedValue(new Error("network exploded"));

    render(<TodayPage />);

    expect(await screen.findByText("network exploded")).toBeInTheDocument();
  });
});
