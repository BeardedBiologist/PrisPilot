import SwiftUI

struct RecipesView: View {
    @Environment(AppStore.self) private var store
    @State private var showAddRecipe = false

    private var personalRecipes: [Recipe] {
        store.recipes.filter { $0.scope == .personal }
    }

    private var householdRecipes: [Recipe] {
        store.recipes.filter { $0.scope == .household }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.recipes.isEmpty {
                    ContentUnavailableView(
                        "No Recipes Yet",
                        systemImage: "fork.knife",
                        description: Text("Ask me in Chat to create a recipe, or add one manually.")
                    )
                } else {
                    if !personalRecipes.isEmpty {
                        Section("Personal") {
                            recipeRows(personalRecipes)
                        }
                    }

                    if !householdRecipes.isEmpty {
                        Section("Household") {
                            recipeRows(householdRecipes)
                        }
                    }
                }
            }
            .navigationTitle("Recipes")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddRecipe = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAddRecipe) {
                AddRecipeSheet().environment(store)
            }
        }
    }

    private func recipeRows(_ recipes: [Recipe]) -> some View {
        ForEach(recipes) { recipe in
            NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                RecipeRow(recipe: recipe)
            }
        }
    }
}

struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.headline)
                HStack {
                    Text(recipe.scope.rawValue)
                    Text("·")
                    Label("\(recipe.servings) servings", systemImage: "person.2")
                    if !recipe.tags.isEmpty {
                        Text("·")
                        Text(recipe.tags.prefix(2).joined(separator: ", "))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if recipe.isFavorite {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

struct RecipeDetailView: View {
    @Environment(AppStore.self) private var store
    let recipe: Recipe

    private var costEstimate: RecipeCostEstimate {
        RecipeCostEstimate(recipe: recipe, observations: store.priceObservations)
    }

    var body: some View {
        List {
            if !recipe.ingredients.isEmpty {
                Section("Ingredients") {
                    ForEach(recipe.ingredients) { ingredient in
                        HStack {
                            Text(ingredient.productName)
                            Spacer()
                            Text("\(ingredient.quantity.formatted()) \(ingredient.unit.rawValue)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Estimated Cost") {
                if costEstimate.matchedIngredients.isEmpty {
                    Text("No recent price data for these ingredients yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(costEstimate.matchedIngredients) { estimate in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(estimate.ingredient.productName)
                                    .font(.subheadline)
                                Text(estimate.observation.storeBranchName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(estimate.detailText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if estimate.bulkRisk != .none {
                                    Label(estimate.bulkRisk.label, systemImage: estimate.bulkRisk.systemImage)
                                        .font(.caption2)
                                        .foregroundStyle(estimate.bulkRisk.color)
                                }
                            }
                            Spacer()
                            Text(currencyText(estimate.estimatedCost, currency: estimate.observation.currency))
                                .font(.subheadline.weight(.semibold))
                        }
                    }

                    HStack {
                        Text("Estimated total")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(currencyText(costEstimate.total, currency: costEstimate.currency))
                            .font(.headline)
                    }

                    Text("Uses proportional unit pricing when units are compatible, otherwise falls back to the recorded package price.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if costEstimate.hasBulkRisk {
                        Text("Bulk warnings flag ingredients where the cheapest package is much larger than this recipe needs.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if !costEstimate.missingIngredients.isEmpty {
                    Text("Missing prices: \(costEstimate.missingIngredients.map(\.productName).joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if !costEstimate.storeTotals.isEmpty {
                Section("Cost by Store") {
                    ForEach(costEstimate.storeTotals) { total in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(total.storeName)
                                        .font(.subheadline.weight(.medium))
                                    if total.id == costEstimate.storeTotals.first?.id {
                                        Text("LOWEST")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.green, in: Capsule())
                                    }
                                }
                                Text("\(total.matchedCount) of \(recipe.ingredients.count) ingredients priced")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if total.missingCount > 0 {
                                    Text("\(total.missingCount) missing price\(total.missingCount == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Text(currencyText(total.total, currency: total.currency))
                                .font(.headline)
                                .foregroundStyle(total.id == costEstimate.storeTotals.first?.id ? .green : .primary)
                        }
                    }
                }
            }

            if !recipe.steps.isEmpty {
                Section("Method") {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { i, step in
                        Label(step, systemImage: "\(i + 1).circle")
                            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    }
                }
            }
        }
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.large)
    }

    private func currencyText(_ value: Decimal, currency: Currency) -> String {
        "\(currency.symbol) \(NSDecimalNumber(decimal: value).stringValue)"
    }
}

private struct RecipeCostEstimate {
    var matchedIngredients: [IngredientCostEstimate]
    var missingIngredients: [RecipeIngredient]
    var storeTotals: [RecipeStoreTotal]
    var total: Decimal
    var currency: Currency
    var hasBulkRisk: Bool { matchedIngredients.contains { $0.bulkRisk != .none } }

    init(recipe: Recipe, observations: [PriceObservation]) {
        let usableObservations = observations.filter { !$0.isStale && !$0.isPromoExpired }
        var matches: [IngredientCostEstimate] = []
        var missing: [RecipeIngredient] = []

        for ingredient in recipe.ingredients {
            if let cheapest = Self.cheapestEstimate(for: ingredient, in: usableObservations) {
                matches.append(cheapest)
            } else {
                missing.append(ingredient)
            }
        }

        matchedIngredients = matches
        missingIngredients = missing
        storeTotals = Self.buildStoreTotals(for: recipe, observations: usableObservations)
        total = matches.reduce(Decimal.zero) { $0 + $1.estimatedCost }
        currency = matches.first?.observation.currency ?? .nok
    }

    private static func buildStoreTotals(for recipe: Recipe, observations: [PriceObservation]) -> [RecipeStoreTotal] {
        let groupedByStore = Dictionary(grouping: observations, by: \.storeBranchID)
        return groupedByStore.compactMap { storeBranchID, storeObservations in
            guard let firstObservation = storeObservations.first else { return nil }
            let estimates = recipe.ingredients.compactMap { ingredient in
                cheapestEstimate(for: ingredient, in: storeObservations)
            }
            guard !estimates.isEmpty else { return nil }

            return RecipeStoreTotal(
                id: storeBranchID,
                storeName: firstObservation.storeBranchName,
                total: estimates.reduce(Decimal.zero) { $0 + $1.estimatedCost },
                matchedCount: estimates.count,
                missingCount: recipe.ingredients.count - estimates.count,
                currency: firstObservation.currency
            )
        }
        .sorted {
            if $0.matchedCount != $1.matchedCount {
                return $0.matchedCount > $1.matchedCount
            }
            return $0.total < $1.total
        }
    }

    private static func cheapestEstimate(for ingredient: RecipeIngredient, in observations: [PriceObservation]) -> IngredientCostEstimate? {
        observations
            .filter { namesMatch(ingredient.productName, $0.productName) }
            .map { observation in
                IngredientCostEstimate(
                    ingredient: ingredient,
                    observation: observation,
                    estimatedCost: estimatedCost(for: ingredient, using: observation),
                    usesUnitConversion: canConvert(ingredient.unit, observation.unit),
                    bulkRisk: bulkRisk(for: ingredient, using: observation)
                )
            }
            .min { lhs, rhs in
                if lhs.usesUnitConversion != rhs.usesUnitConversion {
                    return lhs.usesUnitConversion
                }
                return lhs.estimatedCost < rhs.estimatedCost
            }
    }

    private static func estimatedCost(for ingredient: RecipeIngredient, using observation: PriceObservation) -> Decimal {
        guard let observedQuantity = observation.quantity,
              let observedUnit = observation.unit,
              canConvert(ingredient.unit, observedUnit),
              let requestedBase = baseQuantity(ingredient.quantity, unit: ingredient.unit),
              let observedBase = baseQuantity(observedQuantity, unit: observedUnit),
              observedBase > 0 else {
            return observation.price
        }

        let ratio = Decimal(requestedBase / observedBase)
        return observation.price * ratio
    }

    private static func bulkRisk(for ingredient: RecipeIngredient, using observation: PriceObservation) -> BulkBuyRisk {
        guard let observedQuantity = observation.quantity,
              let observedUnit = observation.unit,
              canConvert(ingredient.unit, observedUnit),
              let requestedBase = baseQuantity(ingredient.quantity, unit: ingredient.unit),
              let observedBase = baseQuantity(observedQuantity, unit: observedUnit),
              requestedBase > 0,
              observedBase > requestedBase else {
            return .none
        }

        let leftoverRatio = (observedBase - requestedBase) / requestedBase
        switch leftoverRatio {
        case 2...:
            return .high
        case 0.75..<2:
            return .medium
        case 0.25..<0.75:
            return .low
        default:
            return .none
        }
    }

    private static func canConvert(_ ingredientUnit: MeasurementUnit, _ observedUnit: MeasurementUnit?) -> Bool {
        guard let observedUnit else { return false }
        return unitFamily(ingredientUnit) == unitFamily(observedUnit)
    }

    private static func baseQuantity(_ quantity: Double, unit: MeasurementUnit) -> Double? {
        switch unit {
        case .grams: return quantity
        case .kilograms: return quantity * 1_000
        case .millilitres: return quantity
        case .litres: return quantity * 1_000
        case .pieces, .packs: return quantity
        }
    }

    private static func unitFamily(_ unit: MeasurementUnit) -> String {
        switch unit {
        case .grams, .kilograms: return "weight"
        case .millilitres, .litres: return "volume"
        case .pieces: return "pieces"
        case .packs: return "packs"
        }
    }

    private static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let leftWords = Set(normalisedWords(lhs))
        let rightWords = Set(normalisedWords(rhs))
        guard !leftWords.isEmpty, !rightWords.isEmpty else { return false }

        let leftText = leftWords.sorted().joined(separator: " ")
        let rightText = rightWords.sorted().joined(separator: " ")
        if leftText == rightText || leftText.contains(rightText) || rightText.contains(leftText) {
            return true
        }

        let overlap = leftWords.intersection(rightWords).count
        let denominator = max(leftWords.union(rightWords).count, 1)
        return Double(overlap) / Double(denominator) >= 0.5
    }

    private static func normalisedWords(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
    }
}

private struct IngredientCostEstimate: Identifiable {
    var id: UUID { ingredient.id }
    let ingredient: RecipeIngredient
    let observation: PriceObservation
    let estimatedCost: Decimal
    let usesUnitConversion: Bool
    let bulkRisk: BulkBuyRisk

    var detailText: String {
        if usesUnitConversion,
           let quantity = observation.quantity,
           let unit = observation.unit {
            return "From kr \(NSDecimalNumber(decimal: observation.price).stringValue) / \(quantity.formatted()) \(unit.rawValue)"
        }
        return "Package price fallback"
    }
}

private enum BulkBuyRisk: Equatable {
    case none
    case low
    case medium
    case high

    var label: String {
        switch self {
        case .none: return ""
        case .low: return "Some leftover"
        case .medium: return "Bulk-buy risk"
        case .high: return "High waste risk"
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "checkmark"
        case .low: return "shippingbox"
        case .medium: return "exclamationmark.triangle"
        case .high: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .none: return .secondary
        case .low: return .secondary
        case .medium: return .orange
        case .high: return .red
        }
    }
}

private struct RecipeStoreTotal: Identifiable {
    let id: UUID
    let storeName: String
    let total: Decimal
    let matchedCount: Int
    let missingCount: Int
    let currency: Currency
}
