import SwiftUI
import Charts

struct ReadinessSparkline: View {
    let points: [ReadinessPoint]
    var body: some View {
        // Overlay pattern: Chart takes parent width only — avoids Charts expanding
        // ScrollView contentSize and enabling left/right page drift on Today.
        Color.clear
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            .overlay {
                Chart(points) { point in
                    LineMark(x: .value("Date", ChartDate.day(point.date)),
                             y: .value("Readiness", point.readiness))
                        .foregroundStyle(Palette.textSecondary)
                        .interpolationMethod(ChartStyle.smooth)
                    PointMark(x: .value("Date", ChartDate.day(point.date)),
                              y: .value("Readiness", point.readiness))
                        .foregroundStyle(point.decision.tint).symbolSize(24)
                }
                .chartYScale(domain: 0 ... 100)
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .chartLegend(.hidden)
            }
            .clipped()
            .allowsHitTesting(false)
    }
}
