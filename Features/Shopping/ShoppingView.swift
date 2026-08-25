import SwiftUI

// MARK: - Shopping Tab Root

struct ShoppingView: View {
    @Environment(AppStore.self) private var store
    @State private var showAddList = false
    @Namespace private var heroSpace

    private var personalLists: [ShoppingList] {
        store.activeLists.filter { $0.scope == .personal }
    }

    private var householdLists: [ShoppingList] {
        store.activeLists.filter { $0.scope == .household }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.activeLists.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
            .reservesFloatingTabBarSpace()
            .navigationTitle("Shopping")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddList = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add shopping list")
                }
            }
            .sheet(isPresented: $showAddList) {
                AddShoppingListSheet().environment(store)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Shopping Lists",
            systemImage: "cart",
            description: Text("Create a list with the + button, or ask the AI in Chat.")
        )
    }

    private var listContent: some View {
        List {
            if !personalLists.isEmpty {
                Section {
                    ForEach(personalLists) { list in
                        listRow(for: list)
                    }
                } header: {
                    if store.household != nil {
                        Text("Personal")
                    }
                }
            }

            if !householdLists.isEmpty {
                Section("Household") {
                    ForEach(householdLists) { list in
                        listRow(for: list)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func listRow(for list: ShoppingList) -> some View {
        NavigationLink(destination: ShoppingListDetailView(listID: list.id, heroNamespace: heroSpace).environment(store)) {
            ShoppingListCard(list: list)
                .matchedTransitionSource(id: list.id, in: heroSpace)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            listContextMenu(for: list)
        }
        .contextMenu {
            listContextMenu(for: list)
        }
    }

    @ViewBuilder
    private func listContextMenu(for list: ShoppingList) -> some View {
        Button(role: .destructive) {
            store.shoppingLists.removeAll { $0.id == list.id }
            store.persistNow()
        } label: {
            Label("Delete List", systemImage: "trash")
        }
    }
}

// MARK: - List Card

struct ShoppingListCard: View {
    let list: ShoppingList

    private var total: Int { list.items.count }
    private var done: Int { list.items.filter { $0.isCompleted }.count }
    private var progress: Double { total == 0 ? 0 : Double(done) / Double(total) }

    private var estimatedTotal: Decimal? {
        let prices = list.items.compactMap { $0.estimatedPrice }
        return prices.isEmpty ? nil : prices.reduce(0, +)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(progress == 1 ? Color.green : Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy, value: progress)
                Text("\(done)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(progress == 1 ? .green : .primary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: done)
            }
            .frame(width: 44, height: 44)

            // Name and subtitle
            VStack(alignment: .leading, spacing: 3) {
                Text(list.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(total == 0 ? "Empty" : "\(total) item\(total == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Total
            VStack(alignment: .trailing, spacing: 2) {
                if let total = estimatedTotal {
                    Text("kr \(formatDecimal(total))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: total)
                    Text("estimated")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if total == 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color(.systemGray3))
                } else {
                    Text("No prices")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    private func formatDecimal(_ d: Decimal) -> String {
        NSDecimalNumber(decimal: d).stringValue
    }
}

// MARK: - List Detail

struct ShoppingListDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let listID: UUID
    /// Set only when pushed from `ShoppingView`'s own list — that's the only
    /// place a matching `matchedTransitionSource` exists. `nil` for other
    /// entry points (e.g. `ActivityTagDetailView`), which fall back to the
    /// default push transition.
    var heroNamespace: Namespace.ID? = nil

    @State private var showAddItem = false
    @State private var showBarcodeScanner = false
    @State private var showComparison = false
    @State private var itemForPriceCapture: ShoppingListItem?
    @State private var optimizationResult: AppStore.OptimizationResult?
    @State private var isOptimizing = false

    private var list: ShoppingList? { store.shoppingLists.first { $0.id == listID } }
    private var listIdx: Int? { store.shoppingLists.firstIndex { $0.id == listID } }

    private var pendingItems: [ShoppingListItem] { list?.items.filter { !$0.isCompleted } ?? [] }
    private var doneItems: [ShoppingListItem] { list?.items.filter { $0.isCompleted } ?? [] }
    private var allDone: Bool { !(list?.items.isEmpty ?? true) && pendingItems.isEmpty }

    // Running totals
    private var actualSpend: Decimal {
        (list?.items.compactMap { $0.actualPrice } ?? []).reduce(0, +)
    }
    private var estimatedRemaining: Decimal {
        (pendingItems.compactMap { $0.estimatedPrice }).reduce(0, +)
    }
    private var hasAnyPrices: Bool {
        list?.items.contains { $0.estimatedPrice != nil || $0.actualPrice != nil } ?? false
    }

    // Store grouping — show when any pending items have a store assignment
    private var useStoreGrouping: Bool {
        pendingItems.contains { $0.assignedStoreBranch != nil }
    }

    private var hasPriceData: Bool {
        !store.priceObservations.isEmpty && !store.enabledBranches.isEmpty
    }

    var body: some View {
        List {
            if let current = list {
                if current.items.isEmpty {
                    ContentUnavailableView(
                        "Empty List",
                        systemImage: "cart.badge.plus",
                        description: Text("Tap + to add items, scan a barcode, or ask the AI in Chat.")
                    )
                } else {
                    totalHeader(current)

                    if useStoreGrouping {
                        storeGroupedSections(current)
                    } else {
                        plainSections()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .reservesFloatingTabBarSpace()
        .navigationTitle(list?.name ?? "List")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 4) {
                    if hasPriceData && !(list?.items.isEmpty ?? true) {
                        Button {
                            runOptimization()
                        } label: {
                            Image(systemName: "wand.and.sparkles")
                                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isOptimizing)
                                .symbolEffectsRemoved(reduceMotion)
                        }
                        .disabled(isOptimizing)
                        .accessibilityLabel("Optimize shopping list")
                    }
                    if !(list?.items.isEmpty ?? true) {
                        Button { showComparison = true } label: {
                            Image(systemName: "chart.bar.xaxis")
                        }
                        .accessibilityLabel("Compare store prices")
                    }
                    Button { showBarcodeScanner = true } label: {
                        Image(systemName: "barcode.viewfinder")
                    }
                    .accessibilityLabel("Scan barcode")
                    Button { showAddItem = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add item")
                }
            }
        }
        .sheet(isPresented: $showAddItem) {
            AddShoppingListItemSheet(listID: listID).environment(store)
        }
        .sheet(isPresented: $showBarcodeScanner) {
            BarcodeScannerView(mode: .addToList(listID)).environment(store)
        }
        .sheet(item: $itemForPriceCapture) { item in
            PriceCaptureSheet(item: item) { price in
                captureActualPrice(for: item.id, price: price)
            }
            .environment(store)
        }
        .navigationDestination(isPresented: $showComparison) {
            if let current = list {
                PriceComparisonView(list: current).environment(store)
            }
        }
        .onAppear {
            autoOptimizeIfNeeded()
        }
        .onChange(of: list?.items.count) { _, _ in
            // Re-optimize whenever items are added or removed
            if hasPriceData { runOptimization() }
        }
        .zoomTransition(id: listID, namespace: heroNamespace)
    }

    // MARK: Total Header

    @ViewBuilder
    private func totalHeader(_ current: ShoppingList) -> some View {
        Section {
            // Optimization banner
            if let result = optimizationResult {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.sparkles")
                            .foregroundStyle(.blue)
                            .font(.caption)
                        Text(result.selectedStores.joined(separator: " + "))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if result.savings > 0 {
                            Text("Saves kr \(formatDecimal(result.savings))")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.15), in: Capsule())
                                .foregroundStyle(.green)
                        }
                    }
                    if result.unassignedCount > 0 {
                        Text("\(result.unassignedCount) item\(result.unassignedCount == 1 ? "" : "s") have no price data yet — record prices in the Prices tab.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 4)
            } else if !hasPriceData && !current.items.isEmpty {
                Label("Record prices in the Prices tab to get store suggestions.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            // Running total
            if hasAnyPrices {
                VStack(spacing: 10) {
                    HStack(alignment: .lastTextBaseline) {
                        if actualSpend > 0 {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("kr \(formatDecimal(actualSpend))")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .contentTransition(.numericText())
                                    .animation(.snappy, value: actualSpend)
                                Text("spent so far")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if estimatedRemaining > 0 {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("≈ kr \(formatDecimal(estimatedRemaining))")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .contentTransition(.numericText())
                                    .animation(.snappy, value: estimatedRemaining)
                                Text("remaining")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if actualSpend == 0 {
                            let est = (current.items.compactMap { $0.estimatedPrice }).reduce(0, +)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("≈ kr \(formatDecimal(est))")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .contentTransition(.numericText())
                                    .animation(.snappy, value: est)
                                Text("estimated total")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    let done = current.items.filter { $0.isCompleted }.count
                    let total = current.items.count
                    ProgressView(value: Double(done), total: Double(total))
                        .tint(allDone ? .green : .blue)
                }
                .padding(.vertical, 4)
            }

            if allDone {
                Label("All done! Great trip.", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: Plain Sections

    @ViewBuilder
    private func plainSections() -> some View {
        if !pendingItems.isEmpty {
            Section("To buy — \(pendingItems.count)") {
                ForEach(pendingItems) { item in
                    itemRow(item)
                }
                .onDelete { offsets in deleteItems(from: pendingItems, at: offsets) }
            }
        }
        if !doneItems.isEmpty {
            Section("Done — \(doneItems.count)") {
                ForEach(doneItems) { item in
                    itemRow(item)
                }
                .onDelete { offsets in deleteItems(from: doneItems, at: offsets) }
            }
        }
    }

    // MARK: Store-Grouped Sections

    @ViewBuilder
    private func storeGroupedSections(_ current: ShoppingList) -> some View {
        ForEach(storeGroups(from: current.items), id: \.store) { group in
            Section(group.store) {
                ForEach(group.items) { item in
                    itemRow(item)
                }
            }
        }
    }

    private struct StoreGroup {
        let store: String
        let items: [ShoppingListItem]
    }

    private func storeGroups(from items: [ShoppingListItem]) -> [StoreGroup] {
        var dict: [String: [ShoppingListItem]] = [:]
        for item in items {
            let key = item.assignedStoreBranch ?? "Unassigned"
            dict[key, default: []].append(item)
        }
        return dict.map { StoreGroup(store: $0.key, items: $0.value) }
            .sorted { lhs, rhs in
                if lhs.store == "Unassigned" { return false }
                if rhs.store == "Unassigned" { return true }
                return lhs.store < rhs.store
            }
    }

    // MARK: Item Row

    @ViewBuilder
    private func itemRow(_ item: ShoppingListItem) -> some View {
        Button {
            toggle(item: item)
        } label: {
            ShoppingItemRow(item: item)
        }
        .buttonStyle(.plain)
    }

    // MARK: Optimization

    private func autoOptimizeIfNeeded() {
        let alreadyAssigned = list?.items.contains { $0.assignedStoreBranch != nil } ?? false
        if hasPriceData && !alreadyAssigned {
            runOptimization()
        } else if alreadyAssigned {
            let stores = Set(list?.items.compactMap { $0.assignedStoreBranch } ?? [])
            if !stores.isEmpty {
                optimizationResult = AppStore.OptimizationResult(
                    selectedStores: stores.sorted(),
                    estimatedTotal: list?.estimatedTotal ?? 0,
                    savings: 0,
                    explanation: "",
                    assignedCount: list?.items.filter { $0.estimatedPrice != nil }.count ?? 0,
                    unassignedCount: list?.items.filter { !$0.isCompleted && $0.estimatedPrice == nil }.count ?? 0
                )
            }
        }
    }

    private func runOptimization() {
        isOptimizing = true
        Task { @MainActor in
            optimizationResult = store.optimizeShoppingList(listID)
            isOptimizing = false
        }
    }

    // MARK: Helpers

    private func toggle(item: ShoppingListItem) {
        guard let idx = listIdx,
              let itemIdx = store.shoppingLists[idx].items.firstIndex(where: { $0.id == item.id }) else { return }
        let nowCompleted = !item.isCompleted
        store.shoppingLists[idx].items[itemIdx].isCompleted = nowCompleted
        store.persistNow()

        if nowCompleted && item.actualPrice == nil {
            itemForPriceCapture = store.shoppingLists[idx].items[itemIdx]
        }
    }

    private func captureActualPrice(for itemID: UUID, price: Decimal?) {
        guard let idx = listIdx,
              let itemIdx = store.shoppingLists[idx].items.firstIndex(where: { $0.id == itemID }) else { return }
        store.shoppingLists[idx].items[itemIdx].actualPrice = price

        let actuals = store.shoppingLists[idx].items.compactMap { $0.actualPrice }
        store.shoppingLists[idx].actualTotal = actuals.isEmpty ? nil : actuals.reduce(0, +)
        store.persistNow()
    }

    private func deleteItems(from items: [ShoppingListItem], at offsets: IndexSet) {
        guard let idx = listIdx else { return }
        let ids = offsets.map { items[$0].id }
        store.shoppingLists[idx].items.removeAll { ids.contains($0.id) }
    }

    private func formatDecimal(_ d: Decimal) -> String {
        NSDecimalNumber(decimal: d).stringValue
    }
}

// MARK: - Item Row View

struct ShoppingItemRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: ShoppingListItem

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.isCompleted ? .green : Color(.systemGray3))
                .font(.title2)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: item.isCompleted)
                .symbolEffectsRemoved(reduceMotion)
                .animation(.snappy, value: item.isCompleted)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.productName)
                    .font(.body)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                HStack(spacing: 4) {
                    Text(item.requestedQuantity)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let variant = item.preferredVariant, !variant.isEmpty {
                        Text("· \(variant)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let notes = item.notes, !notes.isEmpty {
                        Text("· \(notes)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                }
            }

            Spacer()

            if let actual = item.actualPrice {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("kr \(NSDecimalNumber(decimal: actual).stringValue)")
                        .font(.subheadline.weight(.medium))
                        .contentTransition(.numericText())
                        .animation(.snappy, value: actual)
                    Text("paid")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if let estimated = item.estimatedPrice {
                Text("≈ kr \(NSDecimalNumber(decimal: estimated).stringValue)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: estimated)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Price Capture Sheet

struct PriceCaptureSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let item: ShoppingListItem
    let onCapture: (Decimal?) -> Void

    @State private var priceText: String

    init(item: ShoppingListItem, onCapture: @escaping (Decimal?) -> Void) {
        self.item = item
        self.onCapture = onCapture
        _priceText = State(initialValue: item.estimatedPrice.map {
            NSDecimalNumber(decimal: $0).stringValue
        } ?? "")
    }

    private var parsedPrice: Decimal? {
        Decimal(string: priceText.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("kr")
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $priceText)
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    Text("What did you pay for \(item.productName)?")
                } footer: {
                    if let est = item.estimatedPrice {
                        Text("Estimated kr \(NSDecimalNumber(decimal: est).stringValue). Saving the actual price helps future estimates.")
                    } else {
                        Text("Saving the actual price helps future estimates.")
                    }
                }

                if let est = item.estimatedPrice {
                    Section {
                        Button("Confirm estimated (kr \(NSDecimalNumber(decimal: est).stringValue))") {
                            onCapture(est)
                            recordObservation(price: est)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Price Paid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        onCapture(nil)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let price = parsedPrice {
                            onCapture(price)
                            recordObservation(price: price)
                        }
                        dismiss()
                    }
                    .disabled(parsedPrice == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func recordObservation(price: Decimal) {
        let branch: StoreBranch?
        if let name = item.assignedStoreBranch {
            branch = store.enabledBranches.first { $0.displayName == name }
        } else {
            branch = store.enabledBranches.first
        }
        guard let branch else { return }

        let obs = PriceObservation(
            productID: item.productID ?? UUID(),
            productName: item.productName,
            storeBranchID: branch.id,
            storeBranchName: branch.displayName,
            price: price,
            observedDate: Date(),
            source: .manual
        )
        store.priceObservations.append(obs)
        store.queueCommunityContributionIfNeeded(for: obs)
        store.persistNow()
    }
}
