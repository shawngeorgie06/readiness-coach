import SwiftUI
import Charts

struct SleepView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var response: SleepDetailResponse?
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let response, !response.data.isEmpty {
                        SectionCard(title: "Sleep — last \(response.days) days") {
                            Chart(response.data) { day in
                                BarMark(
                                    x: .value("Date", shortDate(day.date)),
                                    y: .value("Hours", day.durationHours)
                                )
                                .foregroundStyle(.blue.opacity(0.5))
                                BarMark(
                                    x: .value("Date", shortDate(day.date)),
                                    y: .value("Restorative", day.restorativeHours)
                                )
                                .foregroundStyle(.indigo)
                            }
                            .frame(height: 220)
                            Text("Bars show total sleep; darker portion is deep + REM (restorative).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if isLoading {
                        ProgressView().padding(.top, 60)
                    } else {
                        ContentUnavailableCompat(
                            title: "No sleep data",
                            message: "Sync from the Today tab to load sleep history.",
                            systemImage: "bed.double"
                        )
                    }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("Sleep")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        guard let client = settings.makeClient() else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            response = try await client.getSleep(days: 30)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func shortDate(_ iso: String) -> String {
        String(iso.suffix(5)) // MM-DD
    }
}
