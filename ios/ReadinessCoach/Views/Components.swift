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

/// Shown above cached content when the latest refresh failed, so saved data
/// never passes for current. Renders nothing otherwise.
struct StaleDataBanner<Value>: View {
    let resource: Resource<Value>
    let retry: () -> Void

    var body: some View {
        if resource.value != nil, resource.error != nil {
            FreshnessBanner(
                title: "Couldn’t refresh",
                message: message,
                color: Palette.warn,
                icon: "exclamationmark.triangle",
                actionTitle: "Retry",
                action: retry
            )
        }
    }

    private var message: String {
        guard let fetchedAt = resource.fetchedAt else { return "Showing saved data." }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Showing data from \(formatter.localizedString(for: fetchedAt, relativeTo: Date()))."
    }
}

/// An ⓘ button that explains a piece of state.
struct InfoBadge: View {
    let title: String
    let message: String
    @State private var show = false
    var body: some View {
        Button { show = true } label: {
            Image(systemName: "info.circle")
                .frame(minWidth: Space.target, minHeight: Space.target)
                .contentShape(Rectangle())
        }
            .buttonStyle(.plain).foregroundStyle(Palette.textSecondary)
            .accessibilityLabel("About \(title)")
            .sheet(isPresented: $show) {
                MessageSheet(title: title, message: message, context: "About this metric")
            }
    }
}
