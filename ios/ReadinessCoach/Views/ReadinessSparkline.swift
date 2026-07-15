import SwiftUI

/// Mini readiness history as caption bars (same idea as Insights trend bars).
/// Not a Swift Charts `Chart` — Charts was expanding Today’s ScrollView
/// content width and enabling left/right page drag.
struct ReadinessSparkline: View {
    let points: [ReadinessPoint]

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: max(2, 4 - Double(points.count) / 20)) {
                ForEach(points) { point in
                    let isLatest = point.id == points.last?.id
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(isLatest ? point.decision.tint : point.decision.tint.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(4, geo.size.height * (point.readiness / 100)))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
        .frame(height: 56)
        .frame(maxWidth: .infinity)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityLabel("Last \(points.count) readiness scores")
    }
}
