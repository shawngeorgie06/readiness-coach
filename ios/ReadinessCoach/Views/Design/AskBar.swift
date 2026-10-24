import SwiftUI

/// The docked "Ask the coach" entry: a quiet field-style button on the one
/// filled surface. It opens the Ask sheet; typing happens there. At
/// accessibility sizes the label shortens and the decorative icons go, so the
/// full action reads at its real size instead of truncating.
struct AskBar: View {
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var large: Bool { typeSize.isAccessibilitySize }
    private var title: String { large ? "Ask the coach" : "Ask the coach anything" }

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            Button(action: action) {
                HStack(spacing: 10) {
                    if !large {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Text(title)
                        .font(.body)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(large ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: large)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !large {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                .padding(.horizontal, large ? 14 : 16)
                .padding(.vertical, large ? 6 : 0)
                .frame(maxWidth: .infinity, minHeight: large ? Space.target : 48)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityInputLabels(["Ask the coach", "Ask the coach anything", "Ask"])
            .accessibilityHint("Opens a question about today's call")
            .accessibilityAddTraits(.isButton)
            .padding(.horizontal, Space.margin)
            .padding(.vertical, large ? 6 : 10)
        }
        .background(Palette.canvas)
    }
}
