import SwiftUI

// Shared presentation for the three pillar tabs (Recovery, Sleep, Train).
// Built from the Today foundation components; nothing here is boxed.

/// ISO-8601 instants from the API, with or without fractional seconds.
enum PillarTime {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let whole: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return fractional.date(from: iso) ?? whole.date(from: iso)
    }

    static func clock(_ iso: String?) -> String? {
        parse(iso)?.formatted(.dateTime.hour().minute())
    }
}

/// Number text without a trailing ".0": 12 → "12", 12.44 → "12.4".
func pillarNumber(_ value: Double) -> String {
    let tenths = (value * 10).rounded() / 10
    return tenths == tenths.rounded() ? String(Int(tenths)) : String(format: "%.1f", tenths)
}

// MARK: - Score head

/// What a pillar tab's head says. The score is today's server pillar score;
/// a missing pillar draws a dash, never a guess.
struct PillarHeadModel: Equatable {
    let pillar: Pillar
    let score: Double?
    let meaning: String
    /// Weight, then any reason to read the score with care.
    let note: String
    let hasCaveat: Bool
    let drivers: [Driver]

    init(pillar: Pillar, today: TodayDTO?, currentDay: String, detail: String? = nil) {
        self.pillar = pillar
        let pillarScore = today.map { pillar.score(in: $0.pillars) }
        score = pillarScore?.score
        drivers = pillarScore?.drivers ?? []
        meaning = detail ?? pillar.summary

        var parts = ["\(pillar.weightPercent)% of readiness"]
        var caveat = false
        if let today {
            if today.date != currentDay, let day = ChartDate.parse(today.date) {
                parts.append("Score from \(day.formatted(.dateTime.month(.abbreviated).day()))")
                caveat = true
            }
            if today.calibrating {
                parts.append("Calibrating to your baseline")
                caveat = true
            }
            if today.isLowConfidence {
                parts.append("Low confidence: some data is missing")
                caveat = true
            }
        } else {
            parts.append("No score yet")
        }
        note = parts.joined(separator: " · ")
        hasCaveat = caveat
    }

    var verdictColor: Color { score.map { ScoreBand(score: $0).color } ?? Palette.textTertiary }

    var accessibilityLabel: String {
        let value = score.map { "\(pillar.title) score \(Int($0.rounded())) out of 100" }
            ?? "\(pillar.title) score unavailable"
        return "\(value). \(meaning). \(note)."
    }
}

/// The pillar head and its driver pills, or a head-shaped placeholder while
/// today's score has never loaded.
struct PillarHead: View {
    let model: PillarHeadModel
    let isLoading: Bool

    var body: some View {
        if isLoading {
            SkeletonHead()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Loading \(model.pillar.title.lowercased()) score")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ScoreHead(
                    score: model.score,
                    verdict: model.pillar.title,
                    verdictColor: model.verdictColor,
                    meaning: model.meaning,
                    note: model.note,
                    noteSystemImage: model.hasCaveat ? "exclamationmark.circle" : nil,
                    accessibilityLabel: model.accessibilityLabel
                )
                if !model.drivers.isEmpty {
                    DriverPills(drivers: model.drivers)
                }
            }
        }
    }
}

/// Outlined driver pills. Tapping one shows its explanation underneath;
/// tapping again hides it. Stacks into a list at accessibility sizes.
struct DriverPills: View {
    let drivers: [Driver]
    @State private var selected: Driver?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(drivers, id: \.self, content: pill)
                }
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(drivers, id: \.self, content: pill)
                }
            }
            if let selected {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selected.text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(selected.detail ?? "No further detail for this driver.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: selected)
    }

    private func pill(_ driver: Driver) -> some View {
        let isOn = selected == driver
        return Button {
            selected = isOn ? nil : driver
        } label: {
            Text(driver.text)
                .font(.subheadline)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isOn ? Palette.surfaceHi : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn ? Palette.accent : Palette.textTertiary.opacity(0.5), lineWidth: 1))
                .frame(minHeight: Space.target)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(driver.text)
        .accessibilityHint(isOn ? "Hides the explanation" : "Shows the explanation")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Lays children out left to right, wrapping onto new lines. Children wider
/// than the line are offered the full width so their text wraps.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +)
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.items.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append((index, size))
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}

// MARK: - Controls and sections

/// One option in a pillar segmented control: a short visible label and the
/// words VoiceOver reads.
struct SegmentOption: Hashable {
    let label: String
    let spoken: String

    init(_ label: String, spoken: String? = nil) {
        self.label = label
        self.spoken = spoken ?? label
    }
}

/// Segmented control on the one filled surface. Every segment is a full
/// 44pt target. Falls back to a menu when the segments don't fit the width.
struct PillarPicker: View {
    let name: String
    let options: [SegmentOption]
    @Binding var selection: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            segments
            menu
        }
    }

    private var segments: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let isOn = index == selection
                Button { selection = index } label: {
                    Text(options[index].label)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(isOn ? Palette.textPrimary : Palette.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(minWidth: Space.target, minHeight: Space.target)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isOn ? Palette.surfaceHi : .clear)
                                .padding(4)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(options[index].spoken)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(name)
    }

    private var menu: some View {
        Menu {
            Picker(name, selection: $selection) {
                ForEach(options.indices, id: \.self) { index in
                    Text(options[index].spoken).tag(index)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(options.indices.contains(selection) ? options[selection].label : "")
                    .multilineTextAlignment(.leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.accent)
            .frame(minHeight: Space.target)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(name)
        .accessibilityValue(options.indices.contains(selection) ? options[selection].spoken : "")
    }
}

/// An open section whose control sits right of the title, or under it at
/// accessibility text sizes so nothing overflows.
struct PillarSection<Control: View, Content: View>: View {
    let title: String
    var showsRule = true
    @ViewBuilder var control: () -> Control
    @ViewBuilder var content: () -> Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            OpenSection(title, showsRule: showsRule) {
                control()
                content()
            }
        } else {
            OpenSection(title: title, showsRule: showsRule, trailing: control, content: content)
        }
    }
}

/// "About …" line that expands an explanation in place.
struct AboutDisclosure: View {
    let explain: MetricExplain
    @State private var isOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                isOpen.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .accessibilityHidden(true)
                    Text(explain.title)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(minHeight: Space.target)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
            if isOpen {
                Text(explain.body)
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isOpen)
    }
}

/// A titled explanation shown in place.
struct MetricExplain: Identifiable, Hashable {
    let title: String
    let body: String
    var id: String { title }
}

// MARK: - States

/// Inline state for a pillar resource: a failed refresh over saved data, a
/// failed first load, or saved data from an earlier day.
/// What a resource notice says, if anything.
enum ResourceNoticeState: Equatable {
    /// A refresh failed; the saved value is still on screen.
    case refreshFailed(error: String)
    /// Nothing is saved and the load failed.
    case loadFailed(error: String)
    /// Healthy saved data from another day.
    case savedFromOtherDay(day: String, refreshing: Bool)

    /// `errorsOnly` drops the healthy saved-day notice for resources whose
    /// date is already shown elsewhere (the score head's "Score from" note).
    static func of<Value>(_ resource: Resource<Value>, currentDay: String, errorsOnly: Bool = false) -> ResourceNoticeState? {
        if let error = resource.error {
            return resource.value != nil ? .refreshFailed(error: error) : .loadFailed(error: error)
        }
        guard !errorsOnly, resource.value != nil, let day = resource.day, day != currentDay else { return nil }
        return .savedFromOtherDay(day: day, refreshing: resource.isRefreshing)
    }
}

struct ResourceNotice<Value>: View {
    let resource: Resource<Value>
    /// e.g. "recovery data".
    let noun: String
    let currentDay: String
    var errorsOnly = false
    let retry: () -> Void

    var body: some View {
        switch ResourceNoticeState.of(resource, currentDay: currentDay, errorsOnly: errorsOnly) {
        case .refreshFailed(let error):
            InlineNotice(
                title: "Couldn't refresh",
                message: "Showing \(noun) saved \(savedAgo). \(error)",
                actionTitle: "Retry",
                action: retry
            )
        case .loadFailed(let error):
            InlineNotice(
                title: "Couldn't load \(noun)",
                message: error,
                systemImage: "wifi.exclamationmark",
                color: Palette.danger,
                actionTitle: "Retry",
                action: retry
            )
        case .savedFromOtherDay(let day, let refreshing):
            InlineNotice(
                title: refreshing ? "Updating" : "Showing saved data",
                message: "This is \(noun) from \(dayText(day)).",
                systemImage: "clock",
                color: Palette.textSecondary
            )
        case nil:
            EmptyView()
        }
    }

    private var savedAgo: String {
        guard let fetchedAt = resource.fetchedAt else { return "earlier" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: fetchedAt, relativeTo: Date())
    }

    private func dayText(_ day: String) -> String {
        ChartDate.parse(day)?.formatted(.dateTime.weekday(.wide).month(.wide).day()) ?? day
    }
}

/// Content-shaped placeholder for a pillar tab's hero and first section.
struct PillarSkeleton: View {
    let name: String
    var heroHeight: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            VStack(alignment: .leading, spacing: 14) {
                SkeletonBlock(width: 120, height: 14)
                SkeletonBlock(height: heroHeight, cornerRadius: 8)
            }
            VStack(alignment: .leading, spacing: 14) {
                Hairline()
                SkeletonBlock(width: 140, height: 14)
                SkeletonLines(count: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading \(name)")
    }
}

/// Nothing to show yet: say why and offer the way to Today, where syncing lives.
struct PillarEmptyState: View {
    let title: String
    let message: String
    let systemImage: String
    @EnvironmentObject private var tabs: TabRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Palette.textTertiary)
                .accessibilityHidden(true)
            Text(title)
                .font(Typeface.sectionTitle)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                tabs.go(to: .today)
            } label: {
                Label("Go to Today", systemImage: "arrow.right")
                    .labelStyle(TrailingIconLabelStyle())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(minHeight: Space.target)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Today is where Health data syncs")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon.accessibilityHidden(true)
        }
    }
}

/// Principal toolbar title for a pillar tab: the tab name over the date.
struct PillarNavTitle: View {
    let title: String
    let day: String

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
            Text(ChartDate.day(day).formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Shared chrome for a pillar tab: canvas, toolbar title, margins.
    func pillarScreen(title: String, day: String) -> some View {
        self
            .screenBackground()
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .principal) { PillarNavTitle(title: title, day: day) }
            }
    }
}
