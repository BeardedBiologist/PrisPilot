import SwiftUI

struct PriceComparisonView: View {
    @Environment(AppStore.self) private var store
    let list: ShoppingList

    private var activeItems: [ShoppingListItem] {
        list.items.filter { !$0.isCompleted }
    }

    private var comparisons: [StoreEstimate] {
        buildComparisons()
    }

    var body: some View {
        List {
            // Summary header
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "tag.fill")
                        .foregroundStyle(.blue)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(activeItems.count) items in list")
                            .font(.subheadline.weight(.medium))
                        Text("Based on \(store.priceObservations.count) recorded price observations")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            // Store estimates
            if comparisons.isEmpty {
                ContentUnavailableView(
                    "No Price Data Yet",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Record prices via Chat or the Prices tab. Then come back here to compare stores.")
                )
            } else {
                Section("Estimated cost by store") {
                    ForEach(comparisons.sorted { $0.estimatedTotal < $1.estimatedTotal }) { estimate in
                        StoreEstimateRow(estimate: estimate, totalItems: activeItems.count, isCheapest: estimate.id == comparisons.min(by: { $0.estimatedTotal < $1.estimatedTotal })?.id)
                    }
                }

                // Per-item best prices
                Section("Cheapest option per item") {
                    ForEach(activeItems) { item in
                        ItemBestPriceRow(item: item, allObservations: store.priceObservations)
                    }
                }
            }
        }
        .navigationTitle("Compare Stores")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Calculation

    struct StoreEstimate: Identifiable {
        let id: UUID
        let branch: StoreBranch
        var estimatedTotal: Decimal
        var matchedItems: Int
        var missingItems: Int
    }

    private func buildComparisons() -> [StoreEstimate] {
        var results: [UUID: StoreEstimate] = [:]

        for branch in store.enabledBranches {
            var total: Decimal = 0
            var matched = 0

            for item in activeItems {
                let obs = latestObservation(for: item.productName, branchID: branch.id)
                if let obs {
                    total += obs.price
                    matched += 1
                }
            }

            guard matched > 0 else { continue }
            results[branch.id] = StoreEstimate(
                id: branch.id,
                branch: branch,
                estimatedTotal: total,
                matchedItems: matched,
                missingItems: activeItems.count - matched
            )
        }

        return Array(results.values)
    }

    private func latestObservation(for productName: String, branchID: UUID) -> PriceObservation? {
        store.priceObservations
            .filter { $0.storeBranchID == branchID && $0.productName.lowercased() == productName.lowercased() }
            .sorted { $0.observedDate > $1.observedDate }
            .first
    }
}

// MARK: - Store Estimate Row

struct StoreEstimateRow: View {
    let estimate: PriceComparisonView.StoreEstimate
    let totalItems: Int
    let isCheapest: Bool

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(estimate.branch.displayName)
                        .font(.subheadline.weight(.medium))
                    if isCheapest {
                        Text("CHEAPEST")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green, in: Capsule())
                    }
                }
                HStack(spacing: 4) {
                    Text("\(estimate.matchedItems) of \(totalItems) items with prices")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if estimate.missingItems > 0 {
                        Text("· \(estimate.missingItems) missing")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            Text("kr \(formatDecimal(estimate.estimatedTotal))")
                .font(.headline)
                .foregroundStyle(isCheapest ? .green : .primary)
        }
        .padding(.vertical, 4)
    }

    private func formatDecimal(_ d: Decimal) -> String {
        NSDecimalNumber(decimal: d).stringValue
    }
}

// MARK: - Item Best Price Row

struct ItemBestPriceRow: View {
    let item: ShoppingListItem
    let allObservations: [PriceObservation]

    private var bestObs: PriceObservation? {
        allObservations
            .filter { $0.productName.lowercased() == item.productName.lowercased() }
            .sorted { $0.price < $1.price }
            .first
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.productName)
                    .font(.subheadline)
                Text(item.requestedQuantity)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let obs = bestObs {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("kr \(NSDecimalNumber(decimal: obs.price).stringValue)")
                        .font(.subheadline.weight(.semibold))
                    Text(obs.storeBranchName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No price data")
                    .font(.caption)
                    .foregroundStyle(Color(.systemGray3))
            }
        }
        .padding(.vertical, 3)
    }
}
