import SwiftUI
import Charts

/// Snaps a continuously-selected x-date (from chart scrubbing) to the nearest
/// plotted date, so the marker and readout land on a real data point.
func nearestDate(_ target: Date?, in dates: [Date]) -> Date? {
    guard let target else { return nil }
    return dates.min(by: {
        abs($0.timeIntervalSince(target)) < abs($1.timeIntervalSince(target))
    })
}

/// Floating readout drawn at the selected point (kept thin — prefer
/// `ScrubDetailBanner` below the chart for the main copy so redraws stay light).
struct ScrubReadout: View {
    let date: Date
    let lines: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(date, format: .dateTime.month().day())
                .font(.caption2.weight(.semibold))
            ForEach(lines, id: \.self) { Text($0).font(.caption2) }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Detail block under a chart. Prefer this over heavy in-chart annotations —
/// updating a Label is much cheaper than rebuilding Chart annotations while scrubbing.
struct ScrubDetailBanner: View {
    let date: Date?
    let placeholder: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let date {
                Text(date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.subheadline.weight(.semibold))
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.primary)
                }
            } else {
                Text(placeholder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Transparent overlay that maps finger x → nearest plotted day.
/// `minimumDistance: 0` so a tap (not only a drag) selects a day.
struct ChartDayScrubOverlay: View {
    let proxy: ChartProxy
    let dates: [Date]
    @Binding var selection: Date?

    var body: some View {
        GeometryReader { _ in
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard let raw: Date = proxy.value(atX: value.location.x),
                                  let snapped = nearestDate(raw, in: dates)
                            else { return }
                            // Only publish when the day changes — avoids laggy full redraws.
                            if snapped != selection {
                                var t = Transaction()
                                t.disablesAnimations = true
                                withTransaction(t) { selection = snapped }
                            }
                        }
                )
        }
    }
}

extension View {
    /// Keeps ScrollViews vertical-only so chart scrubbing can't shove the page off-center.
    func verticalScrollLocked() -> some View {
        self
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}
