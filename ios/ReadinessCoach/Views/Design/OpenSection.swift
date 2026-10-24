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
/// title, grey message, an optional action. Ruled, not boxed. A raw HTTP error
/// is shown as a plain next step; its original text stays behind "Connection
/// details".
struct InlineNotice: View {
    let title: String
    let message: String
    var systemImage = "exclamationmark.triangle"
    var color: Color = Palette.warn
    var actionTitle: String?
    var action: (() -> Void)?
    @State private var showsDetail = false

    var body: some View {
        let copy = NoticeCopy(message: message)
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
                    Text(copy.text)
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                            .frame(minHeight: Space.target)
                    }
                    if let detail = copy.detail {
                        Button {
                            showsDetail.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Text("Connection details")
                                Image(systemName: showsDetail ? "chevron.up" : "chevron.down")
                                    .accessibilityHidden(true)
                            }
                            .font(.footnote)
                            .foregroundStyle(Palette.textTertiary)
                            .frame(minHeight: Space.target)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(showsDetail ? "Expanded" : "Collapsed")
                        if showsDetail {
                            Text(detail)
                                .font(.footnote.monospaced())
                                .foregroundStyle(Palette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What a notice says for a message. `APIError.http` renders as "Server error
/// (404): user_not_found" or "Server returned status 500."; those become a
/// plain next step and keep the original as `detail`. Anything else is already
/// user-facing and passes through.
struct NoticeCopy: Equatable {
    let text: String
    let detail: String?

    init(message: String) {
        guard let status = Self.httpStatus(in: message) else {
            text = message
            detail = nil
            return
        }
        switch status {
        case 404:
            text = "No readiness data was found for this account. Sync Health data or check your connection in Settings."
        case 500...599:
            text = "The server couldn't load this data. Try again shortly."
        default:
            text = "The server couldn't complete this request. Check your account in Settings."
        }
        detail = message
    }

    private static func httpStatus(in message: String) -> Int? {
        for prefix in ["Server error (", "Server returned status "] where message.hasPrefix(prefix) {
            let digits = message.dropFirst(prefix.count).prefix(3)
            guard digits.count == 3, digits.allSatisfy(\.isNumber), let status = Int(digits) else { return nil }
            return (100...599).contains(status) ? status : nil
        }
        return nil
    }
}
