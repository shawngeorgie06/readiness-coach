import SwiftUI

/// Mini readiness history as fixed-width caption bars.
/// No Charts and no GeometryReader — both have widened Today’s ScrollView before.
struct ReadinessSparkline: View {
    let points: [ReadinessPoint]

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(points) { point in
                let isLatest = point.id == points.last?.id
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isLatest ? point.decision.tint : point.decision.tint.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(4, 56 * (point.readiness / 100)))
            }
        }
        .frame(height: 56)
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityLabel("Last \(points.count) readiness scores")
        .accessibilityHidden(true)
    }
}
