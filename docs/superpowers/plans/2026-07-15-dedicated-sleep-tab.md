# Dedicated Sleep Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a sixth **Sleep** tab (Insights-parity: 7d/30d/90d, night selection, stage detail) and deep-link Today/Insights sleep entry points to it.

**Architecture:** Rebuild `SleepView` as a first-class Aether tab matching Insights’ scroll shell and range control. Renumber `AppTab` so Sleep is index 2. Remove sleep sheets from Today/Insights in favor of `TabRouter.go(to: .sleep)`.

**Tech Stack:** SwiftUI, Swift Charts, existing `/v1/sleep` API, Aether `Palette` / `SegmentedRange` / scroll lock helpers.

## Global Constraints

- Tab order: Today · Insights · **Sleep** · Activity · Body · You
- Visual parity with Insights (hidden nav bar, `pageWidthLocked`, `verticalScrollLocked`, screen-head)
- Version stamp **1.2.0 (9)**
- No backend API changes
- No horizontal page rubber-band on Sleep

---

### Task 1: Tab bar + AppTab renumber

**Files:**
- Modify: `ios/ReadinessCoach/Views/RootView.swift`

**Interfaces:**
- Produces: `AppTab.sleep = 2`, Activity/Body/You shifted to 3/4/5
- Consumes: existing `TabRouter`

- [ ] **Step 1:** Update `AppTab` and insert `SleepView()` in `MainTabView` between Insights and Activity with `bed.double.fill`
- [ ] **Step 2:** Commit

### Task 2: Rebuild SleepView (Insights-parity)

**Files:**
- Modify: `ios/ReadinessCoach/Views/SleepView.swift`

**Interfaces:**
- Consumes: `settings.makeClient()?.getSleep(days:)`, `SegmentedRange`, `ChartDate`, `SectionCard`, `InfoBadge`
- Produces: tab-ready `SleepView` (no dismiss toolbar)

- [ ] **Step 1:** Replace sheet-oriented SleepView with full tab: header, range, selected night, night strip, charts
- [ ] **Step 2:** Commit

### Task 3: Deep-links + remove sheets

**Files:**
- Modify: `ios/ReadinessCoach/Views/TodayView.swift`
- Modify: `ios/ReadinessCoach/Views/TrendsView.swift`

- [ ] **Step 1:** Today Sleep tile → `tabs.go(to: .sleep)`; remove sleep sheet
- [ ] **Step 2:** Insights Sleep insight → `tabs.go(to: .sleep)`; remove sleepEntryCard, sheet, `showSleepDetail`
- [ ] **Step 3:** Commit

### Task 4: Version bump + ship

**Files:**
- Modify: `ios/ReadinessCoach/Theme.swift`, `project.pbxproj`, `project.yml`

- [ ] **Step 1:** Stamp **1.2.0 (9)**
- [ ] **Step 2:** Merge to `ios-app-tasks-10-12`, push

## Spec coverage

| Spec item | Task |
|-----------|------|
| Sixth tab order | 1 |
| Insights-parity Sleep UI | 2 |
| Today/Insights → Sleep tab | 3 |
| Version 1.2.0 (9) | 4 |
| Remove Insights sleep charts/sheet | 3 |
