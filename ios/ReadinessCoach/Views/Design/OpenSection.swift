import SwiftUI

/// A 1px rule in the hairline colour, at the screen's real pixel size.
struct Hairline: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1 / max(displayScale, 1))
            .accessibilityHidden(true)
    }
}

/// An open section: a hairline above, a sentence-case title with an optional
/// control at its right, then content straight on the canvas. Never a box.
struct OpenSection<Trailing: View, Content: View>: View {
    let title: String
    var showsRule = true
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsRule { Hairline() }
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(Typeface.sectionTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                trailing()
            }
            .frame(minHeight: 24)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension OpenSection where Trailing == EmptyView {
    init(_ title: String, showsRule: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, showsRule: showsRule, trailing: { EmptyView() }, content: content)
    }
}

/// An inline notice on the canvas (a failed refresh, say): coloured icon and
/// title, grey message, an optional action. Ruled, not boxed.
struct InlineNotice: View {
    let title: String
    let message: String
    var systemImage = "exclamationmark.triangle"
    var color: Color = Palette.warn
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                            .frame(minHeight: Space.target)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
