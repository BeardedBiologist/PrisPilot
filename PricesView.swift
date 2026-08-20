import SwiftUI

struct PricesView: View {
    @Environment(AppStore.self) private var store
    @State private var showAddPrice = false

    var body: some View {
        NavigationStack {
            List {
                if store.priceObservations.isEmpty {
                    ContentUnavailableView(
                        "No Price Data Yet",
                        systemImage: "tag",
                        description: Text("Tell me in Chat what you paid for items and I'll record prices automatically.")
                    )
                } else {
                    ForEach(groupedObservations(), id: \.key) { group in
                        Section(group.key) {
                            ForEach(group.value) { obs in
                                PriceObservationRow(observation: obs)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Prices")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddPrice = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAddPrice) {
                AddPriceObservationSheet().environment(store)
            }
        }
    }

    private func groupedObservations() -> [(key: String, value: [PriceObservation])] {
        let grouped = Dictionary(grouping: store.priceObservations, by: { $0.productName })
        return grouped.map { (key: $0.key, value: $0.value.sorted { $0.observedDate > $1.observedDate }) }
            .sorted { $0.key < $1.key }
    }
}

struct PriceObservationRow: View {
    let observation: PriceObservation

    var priceText: String {
        "\(observation.currency.symbol) \(NSDecimalNumber(decimal: observation.price).stringValue)"
    }

    var quantityText: String? {
        guard let qty = observation.quantity else { return nil }
        let unit = observation.unit?.rawValue ?? ""
        return "\(qty.formatted()) \(unit)"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(observation.storeBranchName)
                    .font(.subheadline)
                if let qty = quantityText {
                    Text(qty)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(observation.observedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(Color(.tertiaryLabel))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(priceText)
                    .font(.subheadline.weight(.semibold))
                if observation.isPromotion {
                    Label("Offer", systemImage: "tag.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                confidencePill
            }
        }
        .padding(.vertical, 3)
    }

    private var confidencePill: some View {
        Text(observation.confidence.rawValue)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(confidenceColor.opacity(0.15), in: Capsule())
            .foregroundStyle(confidenceColor)
    }

    private var confidenceColor: Color {
        switch observation.confidence {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .orange
        case .unconfirmed: return .gray
        }
    }
}
