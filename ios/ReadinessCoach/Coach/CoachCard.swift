import SwiftUI

/// The coach speaking first on Today: one line about the day, two questions
/// that fit it, and a chip for anything else. Text comes from `CoachPrompts`,
/// which reads `TodayDTO` only. `onAsk` gets the tapped question, or nil for
/// "Ask something…".
struct CoachCard: View {
    let today: TodayDTO
    let onAsk: (String?) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                CoachAvatar()
                Text("Coach")
                    .font(Typeface.sectionTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(CoachPrompts.openingLine(today))
                .font(.body)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            ChipFlow(spacing: 8) {
                ForEach(CoachPrompts.suggestions(today), id: \.self) { question in
                    chip(question, systemImage: nil, label: "Ask: \(question)") { onAsk(question) }
                }
                chip("Ask something…", systemImage: "square.and.pencil", label: "Ask the coach a question") {
                    onAsk(nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(shown ? 1 : 0)
        .offset(y: shown || reduceMotion ? 0 : 12)
        .onAppear {
            guard !shown else { return }
            withAnimation(reduceMotion ? .easeIn(duration: 0.25) : .easeOut(duration: 0.4)) { shown = true }
        }
    }

    private func chip(
        _ text: String, systemImage: String?, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityHidden(true)
                }
                Text(text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: Space.target, alignment: .leading)
            .overlay(Capsule().strokeBorder(Palette.stroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Makes a tapped number the source of the coach sheet's zoom. iOS 18 and
/// later only; earlier systems and Reduce Motion get the standard sheet.
struct CoachZoomSource: ViewModifier {
    let id: CoachFocus
    let namespace: Namespace.ID
    let enabled: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18, *), enabled {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

/// The matching destination for `CoachZoomSource`.
struct CoachZoomDestination: ViewModifier {
    let id: CoachFocus
    let namespace: Namespace.ID
    let enabled: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18, *), enabled {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}
