import SwiftUI

/// The anchor of every screen: a huge condensed numeral on the left, the
/// uppercase verdict word and a one-line meaning to its right. Stacks
/// vertically at accessibility text sizes. Tapping, when offered, is one
/// target for the whole head.
struct ScoreHead: View {
    /// The 0–100 score shown verbatim (rounded); nil draws a dash.
    let score: Double?
    /// Shown uppercased and letter-spaced.
    let verdict: String
    let verdictColor: Color
    let meaning: String
    /// An optional quieter line under the meaning.
    var note: String?
    var noteSystemImage: String?
    /// Full VoiceOver sentence for the head.
    let accessibilityLabel: String
    var accessibilityHint: String?
    var action: (() -> Void)?

    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 84
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let action {
            Button(action: action) { head(showsChevron: true) }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint(accessibilityHint ?? "")
                .accessibilityAddTraits(.isButton)
        } else {
            head(showsChevron: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
        }
    }

    private func head(showsChevron: Bool) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 18))
        return layout {
            numeral
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(verdict.uppercased())
                        .font(Typeface.verdict)
                        .tracking(Typeface.verdictTracking)
                        .foregroundStyle(verdictColor)
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                Text(meaning)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    Label {
                        Text(note).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        if let noteSystemImage { Image(systemName: noteSystemImage) }
                    }
                    .font(.footnote)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var numeral: some View {
        Text(score.map { "\(Int($0.rounded()))" } ?? "—")
            .font(Typeface.numeral(min(numeralSize, 132)))
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .fixedSize()
            .contentTransition(reduceMotion ? .identity : .numericText(value: score ?? 0))
            .animation(reduceMotion ? nil : .snappy, value: score)
            // Compressed numerals carry tall built-in leading; trim it so the
            // head sits tight to the verdict.
            .padding(.vertical, -numeralSize * 0.08)
    }
}
