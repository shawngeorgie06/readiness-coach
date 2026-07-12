import SwiftUI

struct PillarInfo: Identifiable {
    let id = UUID()
    let name: String
    let weight: String
    let description: String
    let pillar: PillarScore
}

struct PillarDetailSheet: View {
    let info: PillarInfo
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("\(Int(info.pillar.score.rounded()))")
                            .font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("weight \(info.weight)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(info.description).font(.body)
                    if !info.pillar.drivers.isEmpty {
                        Text("Today's drivers").font(.headline)
                        ForEach(info.pillar.drivers, id: \.self) { d in
                            Label(d, systemImage: "chevron.right.circle").font(.subheadline)
                        }
                    }
                }.padding()
            }
            .navigationTitle(info.name)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
