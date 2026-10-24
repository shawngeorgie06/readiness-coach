import SwiftUI

/// A restrained accent for a sheet's purpose; body copy always stays neutral.
enum SheetTone {
    case neutral, recovery, sleep, load, warning, danger

    var color: Color {
        switch self {
        case .neutral: return Palette.accent
        case .recovery: return Palette.recovery
        case .sleep: return Palette.sleep
        case .load: return Palette.load
        case .warning: return Palette.warn
        case .danger: return Palette.danger
        }
    }
}

/// Shared chrome inside a native `.sheet`. Content and actions scroll together
/// so even accessibility text sizes never lose a dismissal or confirmation.
struct SheetScaffold<Content: View>: View {
    let title: String
    let context: String
    let systemImage: String
    var tone: SheetTone = .neutral
    var onClose: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.section) {
                    SheetHeading(title: title, context: context, systemImage: systemImage, tone: tone, close: close)
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.margin)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .sheetSurface()
        }
        .sheetSurface()
        .presentationDragIndicator(.visible)
        .accessibilityAction(.escape, close)
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }
}

private struct SheetHeading: View {
    let title: String
    let context: String
    let systemImage: String
    let tone: SheetTone
    let close: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(tone.color)
                    .frame(minHeight: Space.target, alignment: .leading)
                    .accessibilityHidden(true)
                Spacer(minLength: 16)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(minWidth: Space.target, minHeight: Space.target)
                        .background(Palette.surfaceHi, in: Circle())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close \(title)")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(context)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.textSecondary)
                Text(title)
                    .font(.largeTitle.weight(.heavy).width(.condensed))
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            .fixedSize(horizontal: false, vertical: true)
            Hairline()
        }
    }
}

enum SheetActionKind { case primary, secondary, destructive }

struct SheetActionStyle: ButtonStyle {
    var kind: SheetActionKind = .primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: Space.target)
            .foregroundStyle(kind == .secondary ? Palette.textPrimary : Palette.canvas)
            .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .contentShape(Rectangle())
    }

    private var fill: Color {
        switch kind {
        case .primary: return Palette.accent
        case .secondary: return Palette.surfaceHi
        case .destructive: return Palette.danger
        }
    }
}

/// Informational and error messages share the same native sheet and readable
/// action. `systemImage` and `context` describe the actual message's subject.
struct MessageSheet: View {
    let title: String
    let message: String
    var systemImage = "info.circle"
    var tone: SheetTone = .neutral
    var context = "Readiness Coach"
    var actionTitle = "OK"

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        SheetScaffold(title: title, context: context, systemImage: systemImage, tone: tone) {
            Text(message)
                .font(.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Button(actionTitle) { dismiss() }
                .buttonStyle(SheetActionStyle())
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
    }
}

/// A presentation can resolve once. Cancellation (including a swipe dismissal)
/// never executes the action, and repeated confirmations cannot execute it twice.
struct SheetConfirmation {
    private enum Resolution { case pending, confirmed, cancelled }
    private var resolution: Resolution = .pending

    @discardableResult
    mutating func confirm(_ action: () -> Void) -> Bool {
        guard resolution == .pending else { return false }
        resolution = .confirmed
        action()
        return true
    }

    mutating func cancel() {
        guard resolution == .pending else { return }
        resolution = .cancelled
    }
}

struct ConfirmationSheet: View {
    let title: String
    let message: String
    let systemImage: String
    let actionTitle: String
    let action: () -> Void

    @State private var confirmation = SheetConfirmation()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetScaffold(title: title, context: "Data & privacy", systemImage: systemImage, tone: .danger, onClose: cancel) {
            Text(message)
                .font(.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 12) {
                Button("Cancel", role: .cancel, action: cancel)
                    .buttonStyle(SheetActionStyle(kind: .secondary))
                Button(actionTitle, role: .destructive) {
                    confirmation.confirm {
                        action()
                        dismiss()
                    }
                }
                .buttonStyle(SheetActionStyle(kind: .destructive))
            }
        }
        .presentationDetents([.large])
        .onDisappear { confirmation.cancel() }
    }

    private func cancel() {
        confirmation.cancel()
        dismiss()
    }
}

extension View {
    /// Opaque brand surface, including the native sheet host and navigation bar.
    func sheetSurface() -> some View {
        self
            .foregroundStyle(Palette.textPrimary)
            .scrollContentBackground(.hidden)
            .background(Palette.surface.ignoresSafeArea())
            .toolbarBackground(Palette.surface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .presentationBackground(Palette.surface)
            .preferredColorScheme(.dark)
    }
}
