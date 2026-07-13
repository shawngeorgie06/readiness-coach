# Train & Sleep Info Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Sleep and Train tabs clearer (plain wording + ⓘ glossaries) and richer (last-night sleep summary with bed/wake times & schedule consistency; weekly training summary).

**Architecture:** One small backend addition (bed/wake timestamps on the sleep detail endpoint) plus iOS presentation changes to `SleepView`, `TrainView`, and `WorkoutRow`. Averages, consistency, and weekly totals are computed on-device from the existing series.

**Tech Stack:** TypeScript + Vitest (backend); SwiftUI + Swift Charts, iOS 17 (app).

## Global Constraints

- Read-only HealthKit; the score, decision, and sleep window are unchanged. This only presents existing data more clearly and adds bed/wake timestamps.
- Tone: concise / scannable, no emoji. Everyday info as inline captions; "what does this mean" via the existing `InfoBadge` (ⓘ).
- Sleep target is a fixed **8h** on iOS (the detail endpoint returns no per-user need; single-user app — matches the 8h the score uses).
- Backend verification: `cd backend && PATH="$HOME/.local/node/bin:$PATH" npm test` (all pass) and `npx tsc --noEmit` (clean).
- iOS (no test target): `cd ios && xcodebuild -project ReadinessCoach.xcodeproj -scheme ReadinessCoach -sdk iphonesimulator -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` → `** BUILD SUCCEEDED **`. Xcode SourceKit "Cannot find type" cross-file diagnostics are index noise — ignore them.
- Commit after each task with the message shown.

---

### Task 1: Backend — bed/wake times on the sleep endpoint

**Files:**
- Modify: `backend/src/services/todayService.ts` (add `sleepBounds`; spread it in `getSleepDetails`)
- Test: `backend/tests/services/todayService.test.ts`

**Interfaces:**
- Produces: `sleepBounds(samples: SleepSample[], windowStart: Date, windowEnd: Date): { sleepStart: string | null; sleepEnd: string | null }`. Each `getSleepDetails` day gains `sleepStart` and `sleepEnd` (ISO strings or null).

- [ ] **Step 1: Write the failing test.** In `backend/tests/services/todayService.test.ts`, add `sleepBounds` to the existing import from `../../src/services/todayService.js`, and add these tests inside the `describe("today aggregation helpers", ...)` block:

```ts
  it("returns the earliest asleep start and latest asleep end in the window", () => {
    const winStart = new Date("2026-07-11T16:00:00.000Z");
    const winEnd = new Date("2026-07-12T16:00:00.000Z");
    const bounds = sleepBounds([
      { startAt: new Date("2026-07-12T04:12:00.000Z"), endAt: new Date("2026-07-12T05:00:00.000Z"), metadata: { stage: "core" } },
      { startAt: new Date("2026-07-12T05:00:00.000Z"), endAt: new Date("2026-07-12T07:20:00.000Z"), metadata: { stage: "rem" } },
      { startAt: new Date("2026-07-12T03:00:00.000Z"), endAt: new Date("2026-07-12T03:30:00.000Z"), metadata: { stage: "inBed" } },
    ], winStart, winEnd);
    expect(bounds.sleepStart).toBe("2026-07-12T04:12:00.000Z");
    expect(bounds.sleepEnd).toBe("2026-07-12T07:20:00.000Z");
  });

  it("returns nulls when no asleep samples overlap the window", () => {
    const bounds = sleepBounds([], new Date("2026-07-11T16:00:00.000Z"), new Date("2026-07-12T16:00:00.000Z"));
    expect(bounds).toEqual({ sleepStart: null, sleepEnd: null });
  });
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `cd backend && PATH="$HOME/.local/node/bin:$PATH" npx vitest run tests/services/todayService.test.ts`
Expected: FAIL — `sleepBounds` is not exported (import error / undefined).

- [ ] **Step 3: Implement `sleepBounds`.** In `backend/src/services/todayService.ts`, add this exported function immediately after `summarizeSleepStages` (it reuses the file-local `sleepStage` helper):

```ts
/** Earliest asleep-sample start and latest asleep-sample end within a night. */
export function sleepBounds(
  samples: SleepSample[],
  windowStart: Date,
  windowEnd: Date,
): { sleepStart: string | null; sleepEnd: string | null } {
  let start: number | null = null;
  let end: number | null = null;
  for (const sample of samples) {
    const stage = sleepStage(sample.metadata);
    if (stage.includes("awake") || stage.includes("inbed")) continue;
    const s = Math.max(sample.startAt.getTime(), windowStart.getTime());
    const e = Math.min(sample.endAt.getTime(), windowEnd.getTime());
    if (e <= s) continue;
    if (start === null || s < start) start = s;
    if (end === null || e > end) end = e;
  }
  return {
    sleepStart: start === null ? null : new Date(start).toISOString(),
    sleepEnd: end === null ? null : new Date(end).toISOString(),
  };
}
```

- [ ] **Step 4: Spread the bounds into each `getSleepDetails` day.** In `getSleepDetails`, change the per-day return object to include the bounds. Replace:

```ts
      return {
        date: day.toISOString().slice(0, 10),
        ...summarizeSleep(samples, window.start, window.end),
        stages: summarizeSleepStages(samples, window.start, window.end),
      };
```

with:

```ts
      return {
        date: day.toISOString().slice(0, 10),
        ...summarizeSleep(samples, window.start, window.end),
        ...sleepBounds(samples, window.start, window.end),
        stages: summarizeSleepStages(samples, window.start, window.end),
      };
```

- [ ] **Step 5: Run the test + full suite + tsc.**

Run: `cd backend && PATH="$HOME/.local/node/bin:$PATH" npx vitest run tests/services/todayService.test.ts && PATH="$HOME/.local/node/bin:$PATH" npm test && PATH="$HOME/.local/node/bin:$PATH" npx tsc --noEmit`
Expected: the two new tests PASS; full suite PASS (44 tests); tsc prints nothing (clean).

- [ ] **Step 6: Commit.**

```bash
git add backend/src/services/todayService.ts backend/tests/services/todayService.test.ts
git commit -m "feat: return bed/wake timestamps from the sleep detail endpoint"
```

---

### Task 2: iOS — Sleep tab last-night summary

**Files:**
- Modify: `ios/ReadinessCoach/Models/DTOs.swift` (`SleepDay` gains `sleepStart`/`sleepEnd`)
- Modify: `ios/ReadinessCoach/Views/SleepView.swift` (summary card + helpers + captions)

**Interfaces:**
- Consumes: `SleepDetailResponse.data: [SleepDay]` now carrying `sleepStart`/`sleepEnd`; existing `InfoBadge(title:message:)`, `SectionCard(title:content:)`, `fmt`.
- Produces: none used elsewhere.

- [ ] **Step 1: Add the optional bed/wake fields to `SleepDay`.** In `ios/ReadinessCoach/Models/DTOs.swift`, replace the `SleepDay` struct with:

```swift
struct SleepDay: Codable, Identifiable {
    let date: String
    let durationHours: Double
    let restorativeHours: Double
    let sleepStart: String?
    let sleepEnd: String?
    let stages: SleepStages
    var id: String { date }
}
```

- [ ] **Step 2: Add the summary card + helpers to `SleepView`.** In `ios/ReadinessCoach/Views/SleepView.swift`, add an ISO parser and helpers, and render a summary card above the charts.

Add, as static/private members of `struct SleepView` (e.g. below `stageColors`):

```swift
    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let needHours = 8.0

    private func clockTime(_ iso: String?) -> String? {
        guard let iso, let date = Self.isoParser.date(from: iso) else { return nil }
        return date.formatted(.dateTime.hour().minute())
    }

    /// Local minutes-past-midnight for a bedtime, or nil.
    private func bedMinutes(_ iso: String?) -> Int? {
        guard let iso, let date = Self.isoParser.date(from: iso) else { return nil }
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        guard let h = c.hour, let m = c.minute else { return nil }
        return h * 60 + m
    }

    private func durationQualifier(_ hours: Double) -> String {
        if hours < 6 { return "well below" }
        if hours < 7.5 { return "a bit below" }
        if hours <= 8.5 { return "right on" }
        return "above"
    }
```

Add the card builder inside `struct SleepView`:

```swift
    @ViewBuilder
    private func summaryCard(_ nights: [SleepDay]) -> some View {
        if let last = nights.last {
            let recent = nights.suffix(7)
            let avg = recent.map(\.durationHours).reduce(0, +) / Double(max(recent.count, 1))
            SectionCard(title: "Last night") {
                Text("You slept \(fmt(last.durationHours))h — \(durationQualifier(last.durationHours)) your 8h target.")
                    .font(.subheadline.weight(.medium))
                if let bed = clockTime(last.sleepStart), let wake = clockTime(last.sleepEnd) {
                    Label("Asleep \(bed) → woke \(wake)", systemImage: "bed.double")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("vs your \(recent.count)-day average of \(fmt(avg))h.")
                    .font(.caption).foregroundStyle(.secondary)
                consistencyRow(nights)
                HStack(spacing: 6) {
                    Text("Deep + REM \(fmt(last.stages.deep + last.stages.rem))h — the recovery stages.")
                        .font(.caption).foregroundStyle(.secondary)
                    InfoBadge(title: "Sleep stages",
                              message: "Deep and REM are when your body and brain recover. Core is lighter sleep; Awake is brief wake-ups. Restorative = deep + REM.")
                }
            }
        }
    }

    @ViewBuilder
    private func consistencyRow(_ nights: [SleepDay]) -> some View {
        let mins = nights.suffix(7).compactMap { bedMinutes($0.sleepStart) }
            .map { ($0 + 720) % 1440 }
        if mins.count >= 3 {
            let mean = Double(mins.reduce(0, +)) / Double(mins.count)
            let variance = mins.map { pow(Double($0) - mean, 2) }.reduce(0, +) / Double(mins.count)
            let std = Int(variance.squareRoot().rounded())
            let label = std <= 30 ? "very consistent"
                : std <= 60 ? "fairly consistent"
                : std <= 90 ? "a little irregular" : "irregular"
            HStack(spacing: 6) {
                Text("Schedule: \(label) (±\(std) min this week).")
                    .font(.caption).foregroundStyle(.secondary)
                InfoBadge(title: "Sleep consistency",
                          message: "Going to bed and waking at similar times helps recovery. This is how much your bedtime varied over the past week.")
            }
        }
    }
```

- [ ] **Step 3: Render the summary card + clearer caption.** In `SleepView.body`, change the populated branch to show the summary first, and update the total-sleep caption. Replace:

```swift
                    if let nights, !nights.isEmpty {
                        totalCard(nights)
                        stageCard(nights)
```

with:

```swift
                    if let nights, !nights.isEmpty {
                        summaryCard(nights)
                        totalCard(nights)
                        stageCard(nights)
```

In `totalCard`, replace the caption line:

```swift
            Text("Darker portion is deep + REM (restorative).")
```

with:

```swift
            Text("Blue is total sleep; darker is deep + REM (restorative).")
```

- [ ] **Step 4: Build.**

Run: `cd ios && xcodebuild -project ReadinessCoach.xcodeproj -scheme ReadinessCoach -sdk iphonesimulator -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit.**

```bash
git add ios/ReadinessCoach/Models/DTOs.swift ios/ReadinessCoach/Views/SleepView.swift
git commit -m "feat: last-night sleep summary with bed/wake, average, and consistency"
```

---

### Task 3: iOS — Train weekly summary + plainer workout metrics

**Files:**
- Modify: `ios/ReadinessCoach/Views/TrainView.swift` (weekly summary card, per-day strain chart, `WorkoutRow` wording + InfoBadges)

**Interfaces:**
- Consumes: `TrainResponse.data: [WorkoutDTO]` (`startAt`, `durationMin`, `strain`, `hrZonesMin`); existing `InfoBadge`, `SectionCard`, `ChartDate.day`.
- Produces: none used elsewhere.

- [ ] **Step 1: Add an ISO parser + weekly-summary + per-day-strain helpers to `TrainView`.** In `ios/ReadinessCoach/Views/TrainView.swift`, add these as private members of `struct TrainView`:

```swift
    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private struct DayStrain: Identifiable {
        let day: Date
        let strain: Double
        var id: Date { day }
    }

    /// One summed-strain bar per calendar day.
    private func dailyStrain(_ workouts: [WorkoutDTO]) -> [DayStrain] {
        let groups = Dictionary(grouping: workouts) { ChartDate.day($0.startAt) }
        return groups.map { DayStrain(day: $0.key, strain: $0.value.reduce(0) { $0 + $1.strain }) }
            .sorted { $0.day < $1.day }
    }

    private func weeklyWorkouts(_ workouts: [WorkoutDTO]) -> [WorkoutDTO] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return workouts.filter { (Self.isoParser.date(from: $0.startAt) ?? .distantPast) >= cutoff }
    }

    private func weekday(_ iso: String) -> String {
        guard let date = Self.isoParser.date(from: iso) else { return "—" }
        return date.formatted(.dateTime.weekday())
    }

    private func formatMinutes(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return total >= 60 ? "\(total / 60)h \(total % 60)m" : "\(total)m"
    }
```

- [ ] **Step 2: Add the weekly summary card builder.** In `struct TrainView`, add:

```swift
    @ViewBuilder
    private func weeklyCard(_ workouts: [WorkoutDTO]) -> some View {
        let week = weeklyWorkouts(workouts)
        if !week.isEmpty {
            let totalStrain = week.reduce(0) { $0 + $1.strain }
            let totalMin = week.reduce(0) { $0 + $1.durationMin }
            let hardest = week.max { $0.strain < $1.strain }
            SectionCard(title: "This week") {
                Text("\(week.count) session\(week.count == 1 ? "" : "s") · \(formatMinutes(totalMin)) · \(Int(totalStrain.rounded())) total strain")
                    .font(.subheadline.weight(.medium))
                if let hardest {
                    Text("Hardest: \(weekday(hardest.startAt)) (\(Int(hardest.strain.rounded())))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
```

- [ ] **Step 3: Render the weekly card + switch the strain chart to per-day.** In `TrainView.body`, in the populated branch, replace:

```swift
                    if let response, !response.data.isEmpty {
                        SectionCard(title: "Strain — last \(response.days) days") {
                            Chart(response.data) { workout in
                                BarMark(
                                    x: .value("Day", ChartDate.day(workout.startAt)),
                                    y: .value("Strain", workout.strain)
                                )
                                .foregroundStyle(.orange)
                            }
                            .frame(height: 200)
                        }
```

with:

```swift
                    if let response, !response.data.isEmpty {
                        weeklyCard(response.data)
                        SectionCard(title: "Daily strain — last \(response.days) days") {
                            Chart(dailyStrain(response.data)) { day in
                                BarMark(
                                    x: .value("Day", day.day),
                                    y: .value("Strain", day.strain)
                                )
                                .foregroundStyle(.orange)
                            }
                            .frame(height: 200)
                        }
```

- [ ] **Step 4: Add a glossary legend to the Workouts card.** In `TrainView.body`, replace the `SectionCard(title: "Workouts")` opening line and its first child so a legend row with both ⓘ badges sits at the top:

```swift
                        SectionCard(title: "Workouts") {
                            HStack(spacing: 6) {
                                Text("Strain 0–21").font(.caption2).foregroundStyle(.secondary)
                                InfoBadge(title: "Strain", message: "Strain rates how hard a session was, 0–21, from heart rate and duration.")
                                Spacer()
                                Text("HR zones").font(.caption2).foregroundStyle(.secondary)
                                InfoBadge(title: "Heart-rate zones", message: "Zones are shares of your session spent at rising heart rates — Easy is a warm-up pace, Max is near your ceiling.")
                            }
                            ForEach(response.data) { workout in
                                WorkoutRow(workout: workout)
                                if workout.id != response.data.last?.id { Divider() }
                            }
                        }
```

- [ ] **Step 5: Plainer strain + zone labels in `WorkoutRow`.** In `WorkoutRow`, add a strain band and rename the zone labels.

Replace the strain `Text` (currently `Text("strain \(String(format: "%.1f", workout.strain))")`) with:

```swift
                    Text("Strain \(Int(workout.strain.rounded())) · \(strainBand(workout.strain))")
                        .font(.subheadline.monospacedDigit())
```

Add the band helper and zone names to `struct WorkoutRow` (replace the existing `zoneColors` line so both live together):

```swift
    private let zoneColors: [Color] = [.gray, .blue, .green, .orange, .red]
    private let zoneNames = ["Easy", "Light", "Moderate", "Hard", "Max"]

    private func strainBand(_ strain: Double) -> String {
        if strain < 8 { return "easy" }
        if strain < 14 { return "moderately hard" }
        if strain < 18 { return "hard" }
        return "all-out"
    }
```

In `zoneBar`, replace the caption expression (the `Text("HR zones · " + ...)` block) with named zones:

```swift
            Text(zones.enumerated()
                .map { "\(zoneNames[min($0.offset, 4)]) \(fmtMin($0.element))m" }
                .joined(separator: "  "))
                .font(.caption2).foregroundStyle(.secondary)
```

- [ ] **Step 6: Build.**

Run: `cd ios && xcodebuild -project ReadinessCoach.xcodeproj -scheme ReadinessCoach -sdk iphonesimulator -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit.**

```bash
git add ios/ReadinessCoach/Views/TrainView.swift
git commit -m "feat: weekly training summary and plainer strain/HR-zone labels"
```

---

## Self-Review

**Spec coverage:**
- Backend bed/wake (`sleepBounds` + endpoint fields + test) → Task 1. ✓
- iOS `SleepDay.sleepStart/sleepEnd` → Task 2 Step 1. ✓
- Sleep summary: duration vs 8h target, bed/wake, vs 7-day avg, consistency (+ⓘ), restorative stages (+ⓘ) → Task 2 Steps 2–3. ✓
- Clearer sleep chart caption → Task 2 Step 3. ✓
- Train weekly summary (sessions, time, total strain, hardest day) → Task 3 Steps 2–3. ✓
- Per-day strain chart aggregation → Task 3 Steps 1, 3. ✓
- Strain band + ⓘ; HR zones Easy/Light/Moderate/Hard/Max + ⓘ → Task 3 Steps 4–5. ✓
- Non-goals (no scrubber here, no scoring change) respected. ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code. ✓

**Type consistency:** `sleepBounds(...) → { sleepStart, sleepEnd }` (TS) matches iOS `SleepDay.sleepStart/sleepEnd: String?`. `DayStrain`, `weeklyWorkouts`, `strainBand`, `zoneNames`, `isoParser` used consistently within Task 3. `InfoBadge(title:message:)`, `SectionCard(title:)`, `ChartDate.day`, `fmt`, `fmtMin` are existing symbols. The `.withFractionalSeconds` parser matches the backend's `toISOString()` (which always emits `.000Z`). ✓
