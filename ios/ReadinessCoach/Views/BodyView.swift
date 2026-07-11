import SwiftUI
import Charts

struct BodyView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var response: BodyResponse?
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let response, !response.data.isEmpty {
                        chartCard(title: "HRV (SDNN, ms)", type: "hrv_sdnn", color: .teal, data: response.data)
                        chartCard(title: "Resting heart rate (bpm)", type: "resting_heart_rate", color: .pink, data: response.data)
                    } else if isLoading {
                        ProgressView().padding(.top, 60)
                    } else {
                        ContentUnavailableCompat(
                            title: "No body metrics",
                            message: "Sync from the Today tab to load HRV and heart rate.",
                            systemImage: "heart"
                        )
                    }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("Body")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    @ViewBuilder
    private func chartCard(title: String, type: String, color: Color, data: [BodySample]) -> some View {
        let points = data
            .filter { $0.type == type && $0.value != nil }
            .compactMap { sample -> (Date, Double)? in
                guard let date = DateFormatting.date(fromISO: sample.startAt), let value = sample.value else { return nil }
                return (date, value)
            }
        if !points.isEmpty {
            SectionCard(title: title) {
                Chart {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Time", point.0), y: .value("Value", point.1))
                            .foregroundStyle(color)
                        PointMark(x: .value("Time", point.0), y: .value("Value", point.1))
                            .foregroundStyle(color)
                            .symbolSize(20)
                    }
                }
                .frame(height: 200)
            }
        }
    }

    private func load() async {
        guard let client = settings.makeClient() else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            response = try await client.getBody(days: 14)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
