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

    private var tripPlan: ShoppingTripPlan? {
        buildTripPlan()
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
                if let tripPlan {
                    Section("Recommended trip") {
                        ShoppingTripPlanView(plan: tripPlan)
                    }
                }

                Section("Estimated cost by store") {
                    ForEach(comparisons.sorted { $0.estimatedTotal < $1.estimatedTotal }) { estimate in
                        StoreEstimateRow(estimate: estimate, totalItems: activeItems.count, isCheapest: estimate.id == comparisons.min(by: { $0.estimatedTotal < $1.estimatedTotal })?.id)
                    }
                }

                // Per-item best prices
                Section("Cheapest option per item") {
                    ForEach(activeItems) { item in
                        ItemBestPriceRow(
                            item: item,
                            allObservations: store.priceObservations,
                            communityConfidence: { store.communityConfidence(for: $0) },
                            isOutlier: { store.isOutlier($0) }
                        )
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

    struct ShoppingTripPlan {
        var selectedStores: [StoreBranch]
        var estimatedTotal: Decimal
        var travelCost: Decimal
        var totalWithTravel: Decimal
        var oneStoreBaseline: StoreEstimate
        var savings: Decimal
        var explanation: String
        var assignedItems: [AssignedItem]
        var excludedStoreNotes: [String]
    }

    struct AssignedItem: Identifiable {
        let id = UUID()
        var itemName: String
        var storeName: String
        var price: Decimal
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
            .filter {
                $0.storeBranchID == branchID &&
                $0.productName.lowercased() == productName.lowercased() &&
                !$0.isPromoExpired &&
                !($0.source == .community && store.isOutlier($0))
            }
            .sorted {
                if $0.freshnessAdjustedConfidence.rank != $1.freshnessAdjustedConfidence.rank {
                    return $0.freshnessAdjustedConfidence.rank > $1.freshnessAdjustedConfidence.rank
                }
                return $0.observedDate > $1.observedDate
            }
            .first
    }

    private func buildTripPlan() -> ShoppingTripPlan? {
        guard let baseline = comparisons.sorted(by: comparisonPriority).first else { return nil }

        var selectedBranchIDs = [baseline.id]
        var selectedBranches = [baseline.branch]
        var assignments = baselineAssignments(for: baseline.branch)
        var total = assignments.reduce(Decimal.zero) { $0 + $1.price }
        var excludedNotes: [String] = []

        let candidates = store.enabledBranches
            .filter { $0.id != baseline.id }
            .compactMap { branch -> StoreCandidate? in
                let improved = improvedAssignments(assignments, using: branch)
                guard improved.savings > 0 else { return nil }
                return StoreCandidate(branch: branch, assignments: improved.assignments, savings: improved.savings)
            }
            .sorted { $0.savings > $1.savings }

        for candidate in candidates {
            if selectedBranchIDs.count >= store.settings.maxSupermarketCount {
                excludedNotes.append("\(candidate.branch.displayName) could save kr \(formatDecimal(candidate.savings)), but max stores is \(store.settings.maxSupermarketCount).")
                continue
            }

            if candidate.savings >= store.settings.minimumAdditionalStoreSavings {
                selectedBranchIDs.append(candidate.branch.id)
                selectedBranches.append(candidate.branch)
                assignments = candidate.assignments
                total -= candidate.savings
            } else {
                excludedNotes.append("\(candidate.branch.displayName) could save kr \(formatDecimal(candidate.savings)), below your kr \(formatDecimal(store.settings.minimumAdditionalStoreSavings)) threshold.")
            }
        }

        let savings = baseline.estimatedTotal - total
        let travelCost = estimatedTravelCost(for: selectedBranches)
        return ShoppingTripPlan(
            selectedStores: selectedBranches,
            estimatedTotal: total,
            travelCost: travelCost,
            totalWithTravel: total + travelCost,
            oneStoreBaseline: baseline,
            savings: savings,
            explanation: explanation(for: selectedBranches, baseline: baseline, savings: savings),
            assignedItems: assignments.sorted { $0.itemName < $1.itemName },
            excludedStoreNotes: excludedNotes
        )
    }

    private func comparisonPriority(_ lhs: StoreEstimate, _ rhs: StoreEstimate) -> Bool {
        if lhs.matchedItems != rhs.matchedItems {
            return lhs.matchedItems > rhs.matchedItems
        }
        return lhs.estimatedTotal < rhs.estimatedTotal
    }

    private func baselineAssignments(for branch: StoreBranch) -> [AssignedItem] {
        activeItems.compactMap { item in
            guard let observation = latestObservation(for: item.productName, branchID: branch.id) else { return nil }
            return AssignedItem(itemName: item.productName, storeName: branch.displayName, price: observation.price)
        }
    }

    private func improvedAssignments(_ current: [AssignedItem], using branch: StoreBranch) -> (assignments: [AssignedItem], savings: Decimal) {
        var updated = current
        var savings = Decimal.zero

        for index in updated.indices {
            guard let cheaper = latestObservation(for: updated[index].itemName, branchID: branch.id),
                  cheaper.price < updated[index].price else { continue }
            savings += updated[index].price - cheaper.price
            updated[index] = AssignedItem(itemName: updated[index].itemName, storeName: branch.displayName, price: cheaper.price)
        }

        return (updated, savings)
    }

    private func explanation(for selectedBranches: [StoreBranch], baseline: StoreEstimate, savings: Decimal) -> String {
        if selectedBranches.count == 1 {
            return "\(baseline.branch.displayName) is the best one-store option for the priced items. No extra store clears your kr \(formatDecimal(store.settings.minimumAdditionalStoreSavings)) saving threshold."
        }

        let storeNames = selectedBranches.map(\.displayName).joined(separator: " + ")
        return "\(storeNames) saves kr \(formatDecimal(savings)) versus shopping only at \(baseline.branch.displayName)."
    }

    private func estimatedTravelCost(for branches: [StoreBranch]) -> Decimal {
        let distanceCost = branches.reduce(Decimal.zero) { partial, branch in
            guard let distance = branch.distanceFromHomeKm else { return partial }
            return partial + Decimal(distance) * store.settings.travelCostPerKilometer
        }
        let stopCost = Decimal(branches.count) * store.settings.fixedStoreVisitCost
        return distanceCost + stopCost
    }

    private func formatDecimal(_ decimal: Decimal) -> String {
        NSDecimalNumber(decimal: decimal).stringValue
    }

    private struct StoreCandidate {
        var branch: StoreBranch
        var assignments: [AssignedItem]
        var savings: Decimal
    }
}

struct ShoppingTripPlanView: View {
    let plan: PriceComparisonView.ShoppingTripPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.selectedStores.map(\.displayName).joined(separator: " + "))
                        .font(.subheadline.weight(.semibold))
                    Text(plan.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("kr \(formatDecimal(plan.estimatedTotal))")
                        .font(.headline)
                    if plan.travelCost > 0 {
                        Text("+ kr \(formatDecimal(plan.travelCost)) travel")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("kr \(formatDecimal(plan.totalWithTravel)) total")
                            .font(.caption.weight(.semibold))
                    }
                    if plan.savings > 0 {
                        Text("Save kr \(formatDecimal(plan.savings))")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            ForEach(plan.assignedItems.prefix(5)) { assignment in
                HStack {
                    Text(assignment.itemName)
                    Spacer()
                    Text(assignment.storeName)
                        .foregroundStyle(.secondary)
                    Text("kr \(formatDecimal(assignment.price))")
                        .font(.caption.weight(.semibold))
                }
                .font(.caption)
            }

            if plan.assignedItems.count > 5 {
                Text("+ \(plan.assignedItems.count - 5) more assigned items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(plan.excludedStoreNotes, id: \.self) { note in
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDecimal(_ decimal: Decimal) -> String {
        NSDecimalNumber(decimal: decimal).stringValue
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
    var communityConfidence: (PriceObservation) -> PriceConfidence = { $0.freshnessAdjustedConfidence }
    var isOutlier: (PriceObservation) -> Bool = { _ in false }

    private var bestObs: PriceObservation? {
        allObservations
            .filter {
                $0.productName.lowercased() == item.productName.lowercased() &&
                !$0.isPromoExpired &&
                !($0.source == .community && isOutlier($0))
            }
            .sorted {
                if $0.freshnessAdjustedConfidence.rank != $1.freshnessAdjustedConfidence.rank {
                    return $0.freshnessAdjustedConfidence.rank > $1.freshnessAdjustedConfidence.rank
                }
                return $0.price < $1.price
            }
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
                    if let priceKind = obs.priceKind, priceKind != .regular {
                        Label(priceKind.rawValue, systemImage: priceKind == .member ? "person.crop.circle.fill" : "star.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    if obs.source == .community {
                        HStack(spacing: 4) {
                            Label("Community", systemImage: "person.3.fill")
                                .foregroundStyle(.purple)
                            Text(communityConfidence(obs).rawValue)
                                .foregroundStyle(isOutlier(obs) ? .red : .secondary)
                        }
                        .font(.caption2)
                    }
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
