import { useEffect, useState } from "react";
import { fetchToday, type Decision, type Pillar, type TodayResponse } from "../api";

const decisionLabel: Record<Decision, string> = {
  push: "Push",
  maintain: "Maintain",
  recover: "Recover",
};

function formatSyncTime(value: string): string {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString();
}

function PillarChip({ name, pillar }: { name: string; pillar: Pillar }) {
  return (
    <section className="pillar" aria-label={`${name} pillar score ${pillar.score}`}>
      <span>{name}</span>
      <strong>{pillar.score}</strong>
      <p>{pillar.drivers[0]?.text ?? "No driver available"}</p>
    </section>
  );
}

function TodayContent({ today }: { today: TodayResponse }) {
  const decisionClass = `decision decision--${today.decision}`;
  return (
    <main className="today-shell">
      <header className="masthead">
        <p className="eyebrow">Readiness Coach · {today.date}</p>
        <h1>Today</h1>
        {today.lastSyncAt && <p className="sync-status">Last synced {formatSyncTime(today.lastSyncAt)}</p>}
      </header>

      {today.calibrating && (
        <aside className="notice">Calibrating: your baseline is still forming. Keep today conservative.</aside>
      )}
      {today.confidence === "low" && (
        <aside className="notice notice--warning">Incomplete data: {today.missing.join(", ") || "some inputs"}. Treat this recommendation conservatively.</aside>
      )}

      <section className="score-card" aria-label="Readiness score and decision">
        <span className="score">{today.readiness}</span>
        <div>
          <p className="eyebrow">Readiness</p>
          <p className={decisionClass}>{decisionLabel[today.decision]}</p>
        </div>
      </section>

      <section className="pillars" aria-label="Readiness pillars">
        <PillarChip name="Sleep" pillar={today.pillars.sleep} />
        <PillarChip name="Recovery" pillar={today.pillars.recovery} />
        <PillarChip name="Load" pillar={today.pillars.load} />
      </section>

      <section className="advisor-card" aria-labelledby="advisor-title">
        <div className="advisor-heading">
          <h2 id="advisor-title">Strict advisor</h2>
          <span className={decisionClass}>{decisionLabel[today.advisor.decision]}</span>
        </div>

        <div className="advisor-block">
          <h3>Why</h3>
          <ul>{today.advisor.why.map((reason) => <li key={reason}>{reason}</li>)}</ul>
        </div>
        <div className="advisor-block">
          <h3>Today’s prescription</h3>
          <p>{today.advisor.prescription}</p>
        </div>
        <div className="advisor-block advisor-block--consequence">
          <h3>If you ignore this</h3>
          <p>{today.advisor.ifIgnored}</p>
        </div>
      </section>

      {today.overridesApplied.length > 0 && (
        <section className="overrides" aria-label="Safety overrides">
          <h2>Safety override</h2>
          <ul>{today.overridesApplied.map((override) => <li key={override}>{override}</li>)}</ul>
        </section>
      )}
    </main>
  );
}

export function TodayPage() {
  const [today, setToday] = useState<TodayResponse>();
  const [error, setError] = useState<string>();

  useEffect(() => {
    const controller = new AbortController();
    fetchToday(controller.signal).then(setToday).catch((reason: unknown) => {
      if (reason instanceof DOMException && reason.name === "AbortError") return;
      setError(reason instanceof Error ? reason.message : "Unable to load today’s readiness.");
    });
    return () => controller.abort();
  }, []);

  if (error) return <main className="state"><h1>Today is unavailable</h1><p>{error}</p></main>;
  if (!today) return <main className="state"><p>Loading today’s readiness…</p></main>;
  return <TodayContent today={today} />;
}
