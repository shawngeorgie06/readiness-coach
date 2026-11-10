import SwiftUI

/// The chat: user bubbles on the right, coach answers on the left, a typing
/// indicator while the coach is working and an inline retry when it fails.
struct CoachThread: View {
    let messages: [CoachMessage]
    let onRetry: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(messages) { message in
                row(message)
                    .transition(arrival)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.45, dampingFraction: 0.85), value: messages)
    }

    /// New messages rise a little as they fade in; Reduce Motion drops the rise.
    private var arrival: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 14))
    }

    @ViewBuilder
    private func row(_ message: CoachMessage) -> some View {
        switch message.role {
        case .user:
            UserBubble(text: message.text)
        case .coach:
            CoachAnswer(message: message, onRetry: onRetry)
        }
    }
}

private struct UserBubble: View {
    let text: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: typeSize.isAccessibilitySize ? 24 : 56)
            Text(text)
                .font(.body)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Palette.surfaceHi, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You: \(text)")
    }
}

/// The coach's mark: a small sparkle in a circle.
struct CoachAvatar: View {
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(Palette.canvas)
            .frame(width: size, height: size)
            .background(Palette.accent, in: Circle())
            .accessibilityHidden(true)
    }
}

private struct CoachAnswer: View {
    let message: CoachMessage
    let onRetry: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CoachAvatar()
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// An answer rises into place; Reduce Motion fades it instead.
    private var swap: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8))
    }

    @ViewBuilder
    private var content: some View {
        switch message.state {
        case .pending:
            TypingIndicator()
                .transition(.opacity)
        case .failed:
            InlineNotice(
                title: "Couldn't get an answer",
                message: (message.failure ?? .other).message,
                actionTitle: "Try again",
                action: onRetry
            )
            .transition(.opacity)
        case .done:
            VStack(alignment: .leading, spacing: 10) {
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.body)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if let note = message.lockNote {
                    Label {
                        Text(note)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "lock.fill")
                    }
                    .font(.footnote)
                    .foregroundStyle(Palette.textTertiary)
                    .labelStyle(TopAlignedLabelStyle())
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Coach: \(message.wireText)")
            .transition(swap)
        }
    }
}

private struct TopAlignedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.font(.caption)
            configuration.title
        }
    }
}

/// Three dots that rise in turn. Under Reduce Motion they hold still and
/// the whole indicator simply fades in and out.
struct TypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var active = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Palette.textSecondary)
                    .frame(width: 7, height: 7)
                    .offset(y: reduceMotion ? 0 : (active ? -4 : 2))
                    .opacity(reduceMotion ? (active ? 1 : 0.35) : 1)
                    .animation(
                        .easeInOut(duration: 0.55).repeatForever(autoreverses: true)
                            .delay(reduceMotion ? 0 : Double(index) * 0.16),
                        value: active
                    )
            }
        }
        .frame(minHeight: 28)
        .padding(.horizontal, 2)
        .onAppear { active = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coach is typing")
    }
}

// MARK: - Chips

/// Suggested questions that wrap onto as many lines as they need.
struct CoachChips: View {
    let questions: [String]
    let onAsk: (String) -> Void

    var body: some View {
        ChipFlow(spacing: 8) {
            ForEach(questions, id: \.self) { question in
                Button { onAsk(question) } label: {
                    Text(question)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minHeight: Space.target, alignment: .leading)
                        .overlay(Capsule().strokeBorder(Palette.stroke, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ask: \(question)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Left-aligned wrapping layout. A child wider than the row takes the full row.
struct ChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return arrange(width: width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > width, width.isFinite {
                size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            }
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return (CGSize(width: width.isFinite ? width : usedWidth, height: y + rowHeight), frames)
    }
}
