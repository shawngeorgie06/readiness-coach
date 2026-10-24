import SwiftUI

/// A placeholder block in the track colour. Static: nothing pulses, so it
/// needs no Reduce Motion handling and never blocks.
struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Palette.track)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// Placeholder shaped like `ScoreHead`: a numeral block, a verdict bar and a
/// meaning line.
struct SkeletonHead: View {
    @ScaledMetric(relativeTo: .largeTitle) private var numeral: CGFloat = 84

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            SkeletonBlock(width: min(numeral, 132) * 1.1, height: min(numeral, 132) * 0.82, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 10) {
                SkeletonBlock(width: 110, height: 18)
                SkeletonBlock(height: 12)
                SkeletonBlock(width: 140, height: 12)
            }
        }
    }
}

/// Placeholder rows of text: full-width lines with a shorter last line.
struct SkeletonLines: View {
    var count = 3
    var lineHeight: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<count, id: \.self) { index in
                if index == count - 1 {
                    SkeletonBlock(width: 160, height: lineHeight)
                } else {
                    SkeletonBlock(height: lineHeight)
                }
            }
        }
    }
}

/// An empty 270° track, the shape of `PillarGauge` before data arrives.
struct SkeletonGauge: View {
    var diameter: CGFloat = 96
    var maxDiameter: CGFloat = 112
    @ScaledMetric(relativeTo: .title) private var scale: CGFloat = 1

    var body: some View {
        let size = min(diameter * scale, maxDiameter)
        VStack(spacing: 8) {
            Circle()
                .trim(from: 0, to: GaugeArc.sweep)
                .rotation(.degrees(GaugeArc.startAngle))
                .stroke(Palette.track, style: StrokeStyle(lineWidth: max(7, size * 0.085), lineCap: .round))
                .frame(width: size, height: size)
            SkeletonBlock(width: 56, height: 12)
        }
    }
}
