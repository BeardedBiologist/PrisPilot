import SwiftUI

/// One store branch's price coverage: everything priced there, how much of
/// it is stale, and — the highest-value bit — which stale prices are
/// currently blocking an active list or recipe, so they're worth
/// re-confirming first.
struct StoreDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let branch: StoreBranch

    /// Latest, non-promo-expired observation per product at this branch.
    private var latestByProduct: [PriceObservation] {
        var latest: [String: PriceObservation] = [:]
        for obs in store.priceObservations where obs.storeBranchID == branch.id && !obs.isPromoExpired {
            let key = obs.productName.lowercased()
            if let existing = latest[key] {
                if obs.observedDate > existing.observedDate { latest[key] = obs }
            } else {
                latest[key] = obs
            }
        }
        return latest.values.sorted { $0.productName < $1.productName }
    }

    private var staleCount: Int { latestByProduct.filter { $0.isStale }.count }

    /// Product names currently needed by an active/planned shopping list or
    /// a saved recipe — used to prioritize which stale prices matter most
    /// to re-confirm, rather than surfacing every stale price equally.
    private var importantProductNames: Set<String> {
        var names = Set<String>()
        for list in store.activeLists + store.plannedLists {
            for item in list.items where !item.isCompleted {
                names.insert(item.productName.lowercased())
            }
        }
        for recipe in store.recipes {
            for ingredient in recipe.ingredients {
                names.insert(ingredient.productName.lowercased())
            }
        }
        return names
    }

    private var importantStaleObservations: [PriceObservation] {
        latestByProduct.filter { $0.isStale && importantProductNames.contains($0.productName.lowercased()) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 24) {
                        statPair(value: "\(latestByProduct.count)", label: latestByProduct.count == 1 ? "product priced" : "products priced")
                        if staleCount > 0 {
                            statPair(value: "\(staleCount)", label: "stale")
                        }
                    }
                    .padding(.vertical, 2)
                }

                if !importantStaleObservations.isEmpty {
                    Section {
                        ForEach(importantStaleObservations) { obs in
                            ConfirmStalePriceRow(observation: obs) {
                                store.confirmPriceObservation(obs.id)
                            }
                        }
                    } header: {
                        Label("Confirm These Prices", systemImage: "exclamationmark.circle.fill")
                    } footer: {
                        Text("Stale, but currently needed by an active list or a saved recipe.")
                    }
                }

                if latestByProduct.isEmpty {
                    ContentUnavailableView(
                        "No Prices Yet",
                        systemImage: "tag",
                        description: Text("No prices have been recorded at \(branch.displayName) yet.")
                    )
                } else {
                    Section("All Products (\(latestByProduct.count))") {
                        ForEach(latestByProduct) { obs in
                            StoreProductRow(observation: obs, currencySymbol: store.settings.currency.symbol)
                        }
                    }
                }
            }
            .navigationTitle(branch.displayName)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func statPair(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.title2.weight(.semibold))
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StoreProductRow: View {
    let observation: PriceObservation
    let currencySymbol: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(observation.productName)
                    .font(.subheadline)
                if let unitPrice = observation.normalizedUnitPrice {
                    Text(unitPrice.formatted(currencySymbol: currencySymbol))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(observation.currency.symbol) \(NSDecimalNumber(decimal: observation.price).stringValue)")
                    .font(.subheadline.weight(.semibold))
                if observation.isStale {
                    Label("Stale", systemImage: "clock.fill")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ConfirmStalePriceRow: View {
    let observation: PriceObservation
    let onConfirm: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(observation.productName)
                    .font(.subheadline)
                Text("Last recorded \(observation.observedDate.formatted(date: .abbreviated, time: .omitted)) · kr \(NSDecimalNumber(decimal: observation.price).stringValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Still Accurate", action: onConfirm)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 3)
    }
}
