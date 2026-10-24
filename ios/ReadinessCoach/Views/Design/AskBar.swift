import SwiftUI

/// The docked "Ask the coach" entry: a quiet field-style button on the one
/// filled surface. It opens the Ask sheet; typing happens there.
struct AskBar: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                    Text("Ask the coach anything")
                        .font(.body)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Palette.textTertiary)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ask the coach anything")
            .accessibilityHint("Opens a question about today's call")
            .accessibilityAddTraits(.isButton)
            .padding(.horizontal, Space.margin)
            .padding(.vertical, 10)
        }
        .background(Palette.canvas)
    }
}
