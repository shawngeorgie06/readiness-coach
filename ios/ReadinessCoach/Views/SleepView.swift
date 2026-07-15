import SwiftUI
import Charts

/// Sleep tab — Insights parity: 7d/30d/90d, tappable nights, stage detail + charts.
struct SleepView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var response: SleepDetailResponse?
    @State private var error: String?
    @State private var isLoading = false
    @State private var rangeIndex = 1
    @State private var selectedNightID: String?

    private let rangeLabels = ["7d", "30d", "90d"]
    private let rangeDays = [7, 30, 90]
    private static let needHours = 8.0

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private let stageColors: [(name: String, color: Color)] = [
        ("Deep", Palette.lavender), ("REM", .purple), ("Core", .blue), ("Awake", Palette.warn),
    ]

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    header
                    SegmentedRange(rangeLabels, selection: $rangeIndex)
                    if let nights, !nights.isEmpty {
                        nightStrip(nights)
                        if let selected = selectedNight(in: nights) {
                            selectedNightCard(selected, in: nights)
                        }
                        totalCard(nights)
                        stageCard(nights)
                    } else if isLoading {
                        ProgressView().padding(.top, 60)
                    } else {
                        ContentUnavailableCompat(
                            title: "No sleep data",
                            message: "Sync from the Today tab to load sleep history. Apple Watch stages appear after HealthKit sync.",
                            systemImage: "bed.double"
                        )
                    }
                    if let error {
                        ErrorCard(message: error) { Task { await load() } }
                    }
                }
                .pageWidthLocked()
                .padding()
            }
            .verticalScrollLocked()
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .task { await load() }
            .refreshable { await load() }
            .onChange(of: rangeIndex) { _, _ in
                selectedNightID = nil
                Task { await load() }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Rest", color: Palette.lavender)
                Text("Sleep")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
            }
            Spacer()
        }
    }

    /// Nights that actually have sleep recorded.
    private var nights: [SleepDay]? {
        response?.data.filter { $0.durationHours > 0 }
    }

    private func selectedNight(in nights: [SleepDay]) -> SleepDay? {
        nights.first(where: { $0.id == selectedNightID }) ?? nights.last
    }

    private func nightStrip(_ nights: [SleepDay]) -> some View {
        let maxHours = max(nights.map(\.durationHours).max() ?? 8, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Tap a night to inspect stages.")
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: max(2, 4 - Double(nights.count) / 30)) {
                    ForEach(nights) { night in
                        let isSelected = night.id == (selectedNightID ?? nights.last?.id)
                        Button {
                            selectedNightID = night.id
                        } label: {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(isSelected ? Palette.lavender : Palette.lavender.opacity(0.45))
                                .frame(maxWidth: .infinity)
                                .frame(height: max(6, geo.size.height * (night.durationHours / maxHours)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(ChartDate.day(night.date).formatted(.dateTime.month().day())), \(fmt(night.durationHours)) hours")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 110)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .onAppear {
            if selectedNightID == nil {
                selectedNightID = nights.last?.id
            }
        }
    }

    private func selectedNightCard(_ night: SleepDay, in nights: [SleepDay]) -> some View {
        let day = ChartDate.day(night.date)
        let recent = nights.suffix(7)
        let avg = recent.map(\.durationHours).reduce(0, +) / Double(max(recent.count, 1))

        return SectionCard(title: "Selected night") {
            Text(day, format: .dateTime.weekday(.wide).month(.wide).day().year())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)

            Text("Slept \(fmt(night.durationHours))h — \(durationQualifier(night.durationHours)) your \(Int(Self.needHours))h target.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let bed = clockTime(night.sleepStart), let wake = clockTime(night.sleepEnd) {
                Label("Asleep \(bed) → woke \(wake)", systemImage: "bed.double")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
            }

            Text("vs your \(recent.count)-night average of \(fmt(avg))h in this window.")
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            consistencyRow(nights)
            stageBreakdown(night)
        }
    }

    private func stageBreakdown(_ night: SleepDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Stages")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                InfoBadge(
                    title: "Sleep stages",
                    message: "Deep and REM are when your body and brain recover. Core is lighter sleep; Awake is brief wake-ups. Restorative = deep + REM."
                )
            }
            stageRow("Deep", night.stages.deep, Palette.lavender)
            stageRow("REM", night.stages.rem, .purple)
            stageRow("Core", night.stages.core, .blue)
            stageRow("Awake", night.stages.awake, Palette.warn)
            Text("Restorative (deep + REM): \(fmt(night.restorativeHours))h")
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, 2)
        }
        .padding(.top, 4)
    }

    private func stageRow(_ name: String, _ hours: Double, _ color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name).font(.subheadline).foregroundStyle(Palette.textPrimary)
            Spacer()
            Text("\(fmt(hours))h")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
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
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                InfoBadge(
                    title: "Sleep consistency",
                    message: "Going to bed and waking at similar times helps recovery. This is how much your bedtime varied over the past week."
                )
            }
        }
    }

    private func totalCard(_ nights: [SleepDay]) -> some View {
        SectionCard(title: "Total sleep — last \(response?.days ?? rangeDays[rangeIndex]) days") {
            Chart(nights) { day in
                BarMark(
                    x: .value("Date", ChartDate.day(day.date)),
                    y: .value("Hours", day.durationHours)
                )
                .foregroundStyle(Palette.lavender.opacity(0.45))
                BarMark(
                    x: .value("Date", ChartDate.day(day.date)),
                    y: .value("Restorative", day.restorativeHours)
                )
                .foregroundStyle(Palette.lavender)
            }
            .frame(height: 200)
            Text("Light bars are total sleep; solid is deep + REM (restorative).")
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stageCard(_ nights: [SleepDay]) -> some View {
        SectionCard(title: "Stages by night") {
            Chart {
                ForEach(nights) { day in
                    stageBar(day, "Deep", day.stages.deep)
                    stageBar(day, "REM", day.stages.rem)
                    stageBar(day, "Core", day.stages.core)
                    stageBar(day, "Awake", day.stages.awake)
                }
            }
            .chartForegroundStyleScale(domain: stageColors.map(\.name), range: stageColors.map(\.color))
            .frame(height: 220)
            if let latest = selectedNight(in: nights) {
                Text("Selected — deep \(fmt(latest.stages.deep))h · REM \(fmt(latest.stages.rem))h · core \(fmt(latest.stages.core))h · awake \(fmt(latest.stages.awake))h")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stageBar(_ day: SleepDay, _ name: String, _ hours: Double) -> some ChartContent {
        BarMark(
            x: .value("Date", ChartDate.day(day.date)),
            y: .value("Hours", hours)
        )
        .foregroundStyle(by: .value("Stage", name))
    }

    private func load() async {
        guard let client = settings.makeClient() else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let days = rangeDays[min(max(rangeIndex, 0), rangeDays.count - 1)]
            response = try await client.getSleep(days: days)
            if selectedNightID == nil || nights?.contains(where: { $0.id == selectedNightID }) != true {
                selectedNightID = nights?.last?.id
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func clockTime(_ iso: String?) -> String? {
        guard let iso, let date = Self.isoParser.date(from: iso) else { return nil }
        return date.formatted(.dateTime.hour().minute())
    }

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

    private func fmt(_ value: Double) -> String { String(format: "%.1f", value) }
}
