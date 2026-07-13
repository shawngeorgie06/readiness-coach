import SwiftUI
import Charts

/// Finger-drag scrubbing for a Swift Chart: maps the touch x-position to the
/// nearest plotted date and reports it via `selected`. The marker persists after
/// release (until the next drag) so the last reading stays visible.
struct ChartScrub: ViewModifier {
    let dates: [Date]
    @Binding var selected: Date?

    func body(content: Content) -> some View {
        content.chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let originX = geo[plotFrame].origin.x
                                let x = value.location.x - originX
                                guard let date: Date = proxy.value(atX: x) else { return }
                                selected = nearest(to: date)
                            }
                    )
            }
        }
    }

    private func nearest(to date: Date) -> Date? {
        dates.min(by: {
            abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date))
        })
    }
}

extension View {
    func chartScrub(dates: [Date], selected: Binding<Date?>) -> some View {
        modifier(ChartScrub(dates: dates, selected: selected))
    }
}

/// Shared floating readout drawn at the selected point.
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
