import Foundation

@MainActor
struct AIEntityResolver {
    enum Resolution<T> {
        case resolved(T)
        case ambiguous([String])
        case missing
        case creatable
    }

    private let appStore: AppStore

    init(appStore: AppStore) {
        self.appStore = appStore
    }

    func shoppingList(named name: String, allowCreate: Bool) -> Resolution<ShoppingList> {
        let query = normalized(name)
        guard !query.isEmpty else { return .missing }

        if isGenericListReference(query) {
            let candidates = appStore.shoppingLists
                .filter { $0.status == .active || $0.status == .planned }
                .sorted { lhs, rhs in statusRank(lhs.status) < statusRank(rhs.status) }
            return resolution(from: candidates, labels: candidates.map(\.name), allowCreate: false)
        }

        let exact = appStore.shoppingLists.filter { normalized($0.name) == query }
        if !exact.isEmpty { return resolution(from: exact, labels: exact.map(\.name), allowCreate: allowCreate) }

        let loose = appStore.shoppingLists.filter { normalized($0.name).contains(query) || query.contains(normalized($0.name)) }
        if !loose.isEmpty { return resolution(from: loose, labels: loose.map(\.name), allowCreate: allowCreate) }

        return allowCreate ? .creatable : .missing
    }

    func shoppingListItem(productName: String, in list: ShoppingList) -> Resolution<ShoppingListItem> {
        let query = normalized(productName)
        guard !query.isEmpty else { return .missing }

        let exact = list.items.filter { normalized($0.productName) == query }
        if !exact.isEmpty { return resolution(from: exact, labels: exact.map(\.productName), allowCreate: false) }

        let loose = list.items.filter { $0.productName.looselyMatchesProductName(productName) }
        if !loose.isEmpty { return resolution(from: loose, labels: loose.map(\.productName), allowCreate: false) }

        return .missing
    }

    func product(named name: String, allowCreate: Bool) -> Resolution<Product> {
        let query = normalized(name)
        guard !query.isEmpty else { return .missing }

        let exact = appStore.products.filter { normalized($0.name) == query }
        if !exact.isEmpty { return resolution(from: exact, labels: exact.map(\.name), allowCreate: allowCreate) }

        let aliasMatches = appStore.products.filter { product in
            product.aliases.contains { normalized($0) == query }
        }
        if !aliasMatches.isEmpty { return resolution(from: aliasMatches, labels: aliasMatches.map(\.name), allowCreate: allowCreate) }

        let loose = appStore.products.filter { $0.name.looselyMatchesProductName(name) }
        if !loose.isEmpty { return resolution(from: loose, labels: loose.map(\.name), allowCreate: allowCreate) }

        return allowCreate ? .creatable : .missing
    }

    func storeBranch(named name: String, allowCreate: Bool) -> Resolution<StoreBranch> {
        let query = normalized(name)
        guard !query.isEmpty else { return .missing }

        let exact = appStore.branches.filter {
            normalized($0.displayName) == query || normalized($0.name) == query
        }
        if !exact.isEmpty { return resolution(from: exact, labels: exact.map(\.displayName), allowCreate: allowCreate) }

        let chainMatches = appStore.branches.filter { normalized($0.chainName) == query }
        if !chainMatches.isEmpty { return resolution(from: chainMatches, labels: chainMatches.map(\.displayName), allowCreate: allowCreate) }

        let loose = appStore.branches.filter {
            normalized($0.displayName).contains(query) || query.contains(normalized($0.displayName)) || normalized($0.chainName).contains(query)
        }
        if !loose.isEmpty { return resolution(from: loose, labels: loose.map(\.displayName), allowCreate: allowCreate) }

        return allowCreate ? .creatable : .missing
    }

    func recipe(named title: String, allowCreate: Bool) -> Resolution<Recipe> {
        let query = normalized(title)
        guard !query.isEmpty else { return .missing }

        let exact = appStore.recipes.filter { normalized($0.title) == query }
        if !exact.isEmpty { return resolution(from: exact, labels: exact.map(\.title), allowCreate: allowCreate) }

        let loose = appStore.recipes.filter { normalized($0.title).contains(query) || query.contains(normalized($0.title)) }
        if !loose.isEmpty { return resolution(from: loose, labels: loose.map(\.title), allowCreate: allowCreate) }

        return allowCreate ? .creatable : .missing
    }

    func matkasseBox(provider: String, allowCreate: Bool) -> Resolution<MatkasseBox> {
        let query = normalized(provider)
        guard !query.isEmpty else { return .missing }

        let exact = appStore.matkasseBoxes.filter { normalized($0.provider) == query }
        if !exact.isEmpty { return resolution(from: exact, labels: exact.map { boxLabel($0) }, allowCreate: allowCreate) }

        let loose = appStore.matkasseBoxes.filter { normalized($0.provider).contains(query) || query.contains(normalized($0.provider)) }
        if !loose.isEmpty { return resolution(from: loose, labels: loose.map { boxLabel($0) }, allowCreate: allowCreate) }

        return allowCreate ? .creatable : .missing
    }

    func memory(matching summary: String) -> Resolution<AIMemory> {
        let queryWords = normalizedWords(summary)
        guard !queryWords.isEmpty else { return .missing }

        let candidates = appStore.activeMemories.filter { memory in
            let memoryWords = normalizedWords(memory.summary)
            guard !memoryWords.isEmpty else { return false }
            let overlap = queryWords.intersection(memoryWords).count
            return Double(overlap) / Double(max(queryWords.count, 1)) >= 0.5
        }
        return resolution(from: candidates, labels: candidates.map(\.summary), allowCreate: false)
    }

    func clarificationQuestion(for entityName: String, candidates: [String]) -> String {
        let options = candidates.prefix(4).joined(separator: ", ")
        return "Which \(entityName) do you mean: \(options)?"
    }

    private func resolution<T>(from matches: [T], labels: [String], allowCreate: Bool) -> Resolution<T> {
        if let only = matches.onlyElement { return .resolved(only) }
        if matches.isEmpty { return allowCreate ? .creatable : .missing }
        return .ambiguous(labels)
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizedWords(_ value: String) -> Set<String> {
        Set(value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 })
    }

    private func isGenericListReference(_ value: String) -> Bool {
        ["list", "the list", "my list", "shopping list", "grocery list", "handleliste"].contains(value)
    }

    private func statusRank(_ status: ListStatus) -> Int {
        switch status {
        case .active: return 0
        case .planned: return 1
        case .completed: return 2
        case .archived: return 3
        }
    }

    private func boxLabel(_ box: MatkasseBox) -> String {
        "\(box.provider) week of \(Self.isoDateFormatter.string(from: box.deliveryWeekStartDate))"
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

private extension Array {
    var onlyElement: Element? {
        count == 1 ? first : nil
    }
}
