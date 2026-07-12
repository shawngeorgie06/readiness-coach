import SwiftUI
import Charts

struct ReadinessSparkline: View {
    let points: [ReadinessPoint]
    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("Date", ChartDate.day(point.date)),
                     y: .value("Readiness", point.readiness))
                .foregroundStyle(.secondary)
            PointMark(x: .value("Date", ChartDate.day(point.date)),
                      y: .value("Readiness", point.readiness))
                .foregroundStyle(point.decision.tint).symbolSize(24)
        }
        .chartYScale(domain: 0 ... 100)
        .chartXAxis(.hidden).chartYAxis(.hidden)
        .frame(height: 56)
    }
}
