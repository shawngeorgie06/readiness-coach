import SwiftUI

struct YouView: View {
    @EnvironmentObject private var settings: AppSettings
    var body: some View {
        SettingsView()   // already a NavigationStack with Connection/Sync/Daily readiness/Data & privacy
    }
}
