import SwiftUI

/// A friendly error surface with a retry affordance.
struct ErrorCard: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Something went wrong", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.warn)
            Text(message).font(.footnote).foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry", action: retry).buttonStyle(.bordered).controlSize(.small).tint(Palette.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// An ⓘ button that explains a piece of state.
struct InfoBadge: View {
    let title: String
    let message: String
    @State private var show = false
    var body: some View {
        Button { show = true } label: { Image(systemName: "info.circle") }
            .buttonStyle(.plain).foregroundStyle(Palette.textSecondary)
            .alert(title, isPresented: $show) { Button("OK", role: .cancel) {} } message: { Text(message) }
    }
}
