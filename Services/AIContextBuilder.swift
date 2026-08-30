import Foundation

@MainActor
struct AIContextBuilder {
    private let appStore: AppStore
    private let now: Date

    init(appStore: AppStore, now: Date = Date()) {
        self.appStore = appStore
        self.now = now
    }

    func build() -> AIContext {
        let scopedMemories = appStore.activeMemories.filter { memory in
            memory.scope == .personal || (memory.scope == .household && appStore.household != nil)
        }

        return AIContext(
            relevantMemories: Array(scopedMemories.prefix(10)),
            availableShoppingLists: appStore.activeLists.prefix(8).map { "\($0.name) (\($0.scope.rawValue))" },
            enabledStoreBranches: storeBranchSummaries(limit: 20),
            userPreferences: scopedMemories.prefix(6).map(\.summary).joined(separator: "; "),
            currency: appStore.settings.currency,
            currentDateISO: Self.isoDateFormatter.string(from: now),
            timeZoneIdentifier: TimeZone.current.identifier,
            localeSummary: localeSummary,
            settingsSummary: settingsSummary,
            shoppingListSummaries: shoppingListSummaries(limit: 10, itemLimit: 6),
            productSummaries: productSummaries(limit: 30),
            recentPriceSummaries: recentPriceSummaries(limit: 20),
            recipeSummaries: recipeSummaries(limit: 15, ingredientLimit: 5),
            mealPlanSummaries: mealPlanSummaries(weekCount: 2),
            matkasseSummaries: matkasseSummaries(limit: 10),
            memorySummaries: scopedMemories.prefix(12).map { memorySummary($0) }
        )
    }

    private var localeSummary: String {
        "Country: \(appStore.settings.country.name) (\(appStore.settings.country.code)); currency: \(appStore.settings.currency.code) (\(appStore.settings.currency.symbol)); language: \(appStore.settings.language); measurement: metric"
    }

    private var settingsSummary: [String] {
        [
            "Cheapest strategy: \(appStore.settings.cheapestDefinition.rawValue)",
            "Maximum stores: \(appStore.settings.maxSupermarketCount)",
            "Minimum extra-store savings: \(formatMoney(appStore.settings.minimumAdditionalStoreSavings))",
            "Travel cost per km: \(formatMoney(appStore.settings.travelCostPerKilometer))",
            "Fixed store visit cost: \(formatMoney(appStore.settings.fixedStoreVisitCost))",
            "Community pricing: \(appStore.settings.participatesInCommunityPricing ? "enabled" : "disabled")"
        ]
    }

    private func shoppingListSummaries(limit: Int, itemLimit: Int) -> [String] {
        appStore.shoppingLists
            .sorted { lhs, rhs in lhs.createdAt > rhs.createdAt }
            .prefix(limit)
            .map { list in
                let pending = list.items.filter { !$0.isCompleted }
                let completedCount = list.items.count - pending.count
                let items = pending.prefix(itemLimit).map { item in
                    var parts = ["\(item.productName) x \(item.requestedQuantity)"]
                    if let store = item.assignedStoreBranch { parts.append("store: \(store)") }
                    if let price = item.estimatedPrice { parts.append("est: \(formatMoney(price))") }
                    return parts.joined(separator: ", ")
                }
                let planned = list.plannedDate.map { "; planned: \(Self.isoDateFormatter.string(from: $0))" } ?? ""
                let itemText = items.isEmpty ? "no pending items" : items.joined(separator: " | ")
                return "\(list.name) [\(list.status.rawValue), \(list.scope.rawValue), pending: \(pending.count), completed: \(completedCount)\(planned)] -> \(itemText)"
            }
    }

    private func storeBranchSummaries(limit: Int) -> [String] {
        appStore.branches
            .sorted { $0.displayName < $1.displayName }
            .prefix(limit)
            .map { branch in
                var parts = [branch.displayName, branch.isEnabled ? "enabled" : "disabled"]
                if let distance = branch.distanceFromHomeKm { parts.append("\(distance.formatted()) km") }
                if let address = branch.address { parts.append(address) }
                return parts.joined(separator: " · ")
            }
    }

    private func productSummaries(limit: Int) -> [String] {
        appStore.products
            .sorted { $0.name < $1.name }
            .prefix(limit)
            .map { product in
                var parts = [product.name]
                if let category = product.category { parts.append(category) }
                if let unit = product.defaultUnit { parts.append("unit: \(unit.rawValue)") }
                if !product.aliases.isEmpty { parts.append("aliases: \(product.aliases.prefix(4).joined(separator: ", "))") }
                if product.barcode != nil { parts.append("barcode saved") }
                return parts.joined(separator: " · ")
            }
    }

    private func recentPriceSummaries(limit: Int) -> [String] {
        appStore.priceObservations
            .sorted { $0.observedDate > $1.observedDate }
            .prefix(limit)
            .map { observation in
                var parts = [
                    observation.productName,
                    observation.storeBranchName,
                    formatMoney(observation.price),
                    Self.isoDateFormatter.string(from: observation.observedDate),
                    observation.source.rawValue,
                    observation.freshnessAdjustedConfidence.rawValue
                ]
                if let quantity = observation.quantity, let unit = observation.unit {
                    parts.insert("\(quantity.formatted()) \(unit.rawValue)", at: 3)
                }
                if observation.isPromotion { parts.append("promotion") }
                if observation.isStale { parts.append("stale") }
                return parts.joined(separator: " · ")
            }
    }

    private func recipeSummaries(limit: Int, ingredientLimit: Int) -> [String] {
        appStore.recipes
            .sorted { $0.title < $1.title }
            .prefix(limit)
            .map { recipe in
                let ingredients = recipe.ingredients.prefix(ingredientLimit).map { ingredient in
                    "\(ingredient.productName) \(ingredient.quantity.formatted()) \(ingredient.unit.rawValue)"
                }
                let ingredientText = ingredients.isEmpty ? "no ingredients saved" : ingredients.joined(separator: ", ")
                return "\(recipe.title) [servings: \(recipe.servings), \(recipe.scope.rawValue)] -> \(ingredientText)"
            }
    }

    private func mealPlanSummaries(weekCount: Int) -> [String] {
        let currentWeekStart = appStore.weekStartDate(for: now)
        let weekStarts = (0..<weekCount).compactMap {
            Calendar.mealPlanCalendar.date(byAdding: .weekOfYear, value: $0, to: currentWeekStart)
        }
        let dayRange = weekStarts.flatMap { weekStart in
            (0..<7).compactMap { Calendar.mealPlanCalendar.date(byAdding: .day, value: $0, to: weekStart) }
        }
        return appStore.mealPlanSlots(on: dayRange)
            .sorted { lhs, rhs in lhs.date == rhs.date ? lhs.mealType.displayName < rhs.mealType.displayName : lhs.date < rhs.date }
            .map { slot in
                "\(Self.isoDateFormatter.string(from: slot.date)) \(slot.mealType.displayName): \(mealSlotContentSummary(slot.content))\(slot.isLeftover ? " (leftover)" : "")"
            }
    }

    private func matkasseSummaries(limit: Int) -> [String] {
        appStore.matkasseBoxes
            .sorted { $0.deliveryWeekStartDate < $1.deliveryWeekStartDate }
            .prefix(limit)
            .map { box in
                let meals = box.includedMeals.prefix(5).map(\.title).joined(separator: ", ")
                let mealText = meals.isEmpty ? "no meals saved" : meals
                let priceText = box.price.map { "; price: \(formatMoney($0))" } ?? ""
                return "\(box.provider) [week: \(Self.isoDateFormatter.string(from: box.deliveryWeekStartDate)); meals: \(box.numberOfMeals); servings: \(box.servingsPerMeal)\(priceText)] -> \(mealText)"
            }
    }

    private func memorySummary(_ memory: AIMemory) -> String {
        "\(memory.summary) [\(memory.category.rawValue), \(memory.strength.rawValue), \(memory.scope.rawValue), \(memory.sensitivityLevel.rawValue)]"
    }

    private func mealSlotContentSummary(_ content: MealSlotContent) -> String {
        switch content {
        case .recipe(_, let title):
            return "recipe: \(title)"
        case .matkasseMeal(_, let title):
            return "matkasse: \(title)"
        case .freeform(let text):
            return text
        case .eatingOut(let note):
            return note.map { "eating out: \($0)" } ?? "eating out"
        }
    }

    private func formatMoney(_ value: Decimal) -> String {
        "\(appStore.settings.currency.symbol) \(NSDecimalNumber(decimal: value).stringValue)"
    }

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
