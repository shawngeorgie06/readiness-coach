import SwiftUI
import Charts

struct ReadinessSparkline: View {
    let points: [ReadinessPoint]
    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("Date", ChartDate.day(point.date)),
                     y: .value("Readiness", point.readiness))
                .foregroundStyle(.secondary)
                .interpolationMethod(ChartStyle.smooth)
            PointMark(x: .value("Date", ChartDate.day(point.date)),
                      y: .value("Readiness", point.readiness))
                .foregroundStyle(point.decision.tint).symbolSize(24)
        }
        .chartYScale(domain: 0 ... 100)
        .chartXAxis(.hidden).chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .clipped()
        .allowsHitTesting(false) // decorative — don’t let chart pans shove Today sideways
    }
}
