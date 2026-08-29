import SwiftUI

// MARK: - List Detail

struct ShoppingListDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.switchToSettingsTab) private var switchToSettingsTab
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
    @State private var itemForAddPrice: ShoppingListItem?
    @State private var itemForMove: ShoppingListItem?
    @State private var itemForSubstitute: ShoppingListItem?
    @State private var optimizationResult: AppStore.OptimizationResult?
    @State private var isOptimizing = false
    @State private var forceOneStore = false
    @State private var showCompleted = false
    @State private var showInStoreMode = false

    private var list: ShoppingList? { store.shoppingLists.first { $0.id == listID } }
    private var listIdx: Int? { store.shoppingLists.firstIndex { $0.id == listID } }

    private var pendingItems: [ShoppingListItem] { list?.items.filter { !$0.isCompleted } ?? [] }
    private var pricedPendingItems: [ShoppingListItem] { pendingItems.filter { $0.estimatedPrice != nil } }
    private var needsPriceItems: [ShoppingListItem] { pendingItems.filter { $0.estimatedPrice == nil } }
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

    private var hasPriceData: Bool {
        !store.priceObservations.isEmpty && !store.enabledBranches.isEmpty
    }

    private var firstStoreWithPendingItems: String? {
        pricedPendingItems.compactMap(\.assignedStoreBranch).sorted().first
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
                    tripSummarySection(current)
                    optimizationControlsSection

                    storeGroupedSections()
                    needsPriceSection()
                    completedSection()
                    archiveSection(current)
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
                    if firstStoreWithPendingItems != nil {
                        Button { showInStoreMode = true } label: {
                            Image(systemName: "checklist")
                        }
                        .accessibilityLabel("In-store mode")
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
        .sheet(item: $itemForAddPrice, onDismiss: { if hasPriceData { runOptimization() } }) { item in
            AddPriceObservationSheet(prefilledProductName: item.productName).environment(store)
        }
        .sheet(item: $itemForMove) { item in
            MoveItemToStoreSheet(item: item, listID: listID).environment(store)
        }
        .sheet(item: $itemForSubstitute) { item in
            SubstituteItemSheet(item: item, listID: listID).environment(store)
        }
        .navigationDestination(isPresented: $showComparison) {
            if let current = list {
                PriceComparisonView(list: current).environment(store)
            }
        }
        .fullScreenCover(isPresented: $showInStoreMode) {
            if let initialStore = firstStoreWithPendingItems {
                InStoreModeView(listID: listID, initialStore: initialStore).environment(store)
            }
        }
        .onAppear {
            autoOptimizeIfNeeded()
        }
        .onChange(of: list?.items.count) { _, _ in
            // Re-optimize whenever items are added or removed
            if hasPriceData { runOptimization() }
        }
        .onChange(of: forceOneStore) { _, _ in
            if hasPriceData { runOptimization() }
        }
        .zoomTransition(id: listID, namespace: heroNamespace)
    }

    // MARK: Trip Summary Band

    @ViewBuilder
    private func tripSummarySection(_ current: ShoppingList) -> some View {
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
                        Text("\(result.unassignedCount) item\(result.unassignedCount == 1 ? "" : "s") have no price data yet — see Needs Price Data below.")
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

            // Store / priced coverage stat pair
            if let result = optimizationResult ?? fallbackResult(from: current) {
                HStack(spacing: 20) {
                    statPair(value: "\(result.selectedStores.count)", label: result.selectedStores.count == 1 ? "store" : "stores")
                    statPair(value: "\(result.assignedCount)/\(result.assignedCount + result.unassignedCount)", label: "priced")
                }
                .padding(.vertical, 2)
            }

            // Running total
            if hasAnyPrices {
                VStack(spacing: 8) {
                    HStack(alignment: .lastTextBaseline) {
                        if actualSpend > 0 {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("kr \(formatDecimal(actualSpend))")
                                    .font(.title2.weight(.bold))
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
                                    .font(.callout.weight(.semibold))
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
                                    .font(.title2.weight(.bold))
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
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private func statPair(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Synthesizes a display-only result from the list's last saved
    /// `optimizationSnapshot` when the view hasn't run the optimizer itself
    /// this session (e.g. reopening an already-optimized list).
    private func fallbackResult(from current: ShoppingList) -> AppStore.OptimizationResult? {
        guard let snapshot = current.optimizationSnapshot else { return nil }
        return AppStore.OptimizationResult(
            selectedStores: snapshot.chosenStores,
            estimatedTotal: snapshot.optimizedTotal,
            savings: snapshot.savings,
            explanation: "",
            assignedCount: pendingItems.count - snapshot.unpricedItemCount,
            unassignedCount: snapshot.unpricedItemCount
        )
    }

    // MARK: Optimization Controls

    private var optimizationControlsSection: some View {
        Section("Optimization") {
            Toggle("Force one store", isOn: $forceOneStore)

            Button {
                switchToSettingsTab()
            } label: {
                HStack {
                    Text("Up to \(store.settings.maxSupermarketCount) store\(store.settings.maxSupermarketCount == 1 ? "" : "s") · saves ≥ kr \(formatDecimal(store.settings.minimumAdditionalStoreSavings)) to add one")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Store-Grouped Sections

    private struct StoreGroup {
        let store: String
        let items: [ShoppingListItem]
        var subtotal: Decimal { items.compactMap(\.estimatedPrice).reduce(0, +) }
    }

    @ViewBuilder
    private func storeGroupedSections() -> some View {
        ForEach(storeGroups(from: pricedPendingItems), id: \.store) { group in
            Section {
                ForEach(group.items) { item in
                    itemRow(item)
                }
            } header: {
                HStack {
                    Text(group.store)
                    if hasLowConfidence(group.items) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Text("\(group.items.count) · kr \(formatDecimal(group.subtotal))")
                        .foregroundStyle(.secondary)
                }
                .textCase(nil)
            }
        }
    }

    private func storeGroups(from items: [ShoppingListItem]) -> [StoreGroup] {
        var dict: [String: [ShoppingListItem]] = [:]
        for item in items {
            let key = item.assignedStoreBranch ?? "Unassigned"
            dict[key, default: []].append(item)
        }
        return dict.map { StoreGroup(store: $0.key, items: $0.value) }
            .sorted { $0.store < $1.store }
    }

    /// True when any item in the group's price came from an observation
    /// whose freshness-adjusted confidence has dropped to Low/Unconfirmed —
    /// surfaced as a small warning next to the store subtotal rather than
    /// per-item, to keep the row itself uncluttered.
    private func hasLowConfidence(_ items: [ShoppingListItem]) -> Bool {
        items.contains { item in
            guard let obsID = item.selectedPriceObservationID,
                  let obs = store.priceObservations.first(where: { $0.id == obsID }) else { return false }
            return obs.freshnessAdjustedConfidence.rank <= PriceConfidence.low.rank
        }
    }

    // MARK: Needs Price Data

    @ViewBuilder
    private func needsPriceSection() -> some View {
        if !needsPriceItems.isEmpty {
            Section {
                ForEach(needsPriceItems) { item in
                    NeedsPriceItemRow(
                        item: item,
                        hasCommunityPrice: communityPriceExists(for: item.productName),
                        onAddPrice: { itemForAddPrice = item },
                        onUseCommunity: { useCommunityPrice(for: item) },
                        onScanBarcode: { showBarcodeScanner = true }
                    )
                }
            } header: {
                Label("Needs Price Data — \(needsPriceItems.count)", systemImage: "questionmark.circle")
            }
        }
    }

    private func communityPriceExists(for productName: String) -> Bool {
        store.priceObservations.contains {
            $0.source == .community &&
            $0.productName.lowercased() == productName.lowercased() &&
            !$0.isPromoExpired
        }
    }

    private func useCommunityPrice(for item: ShoppingListItem) {
        let candidates = store.priceObservations.filter {
            $0.source == .community &&
            $0.productName.lowercased() == item.productName.lowercased() &&
            !$0.isPromoExpired
        }
        guard let best = candidates.min(by: { $0.price < $1.price }) else { return }
        store.assignPriceObservation(best.id, toItem: item.id, in: listID)
    }

    // MARK: Completed Section

    @ViewBuilder
    private func completedSection() -> some View {
        if !doneItems.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $showCompleted) {
                    ForEach(doneItems) { item in
                        completedItemRow(item)
                    }
                } label: {
                    HStack {
                        Text("Completed")
                        Spacer()
                        Text("\(doneItems.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Archive Section

    @ViewBuilder
    private func archiveSection(_ current: ShoppingList) -> some View {
        if current.status != .archived {
            Section {
                Button(role: .destructive) {
                    store.archiveShoppingList(listID)
                } label: {
                    Label("Archive List", systemImage: "archivebox")
                        .font(.callout)
                }
            }
        }
    }

    private func completedItemRow(_ item: ShoppingListItem) -> some View {
        ShoppingItemRow(item: item)
            .contentShape(Rectangle())
            .onTapGesture { toggle(item: item) }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    store.undoCompleteItem(item.id, in: listID)
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .tint(.blue)
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { itemForMove = item } label: {
                Label("Move", systemImage: "arrow.left.arrow.right")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { itemForSubstitute = item } label: {
                Label("Substitute", systemImage: "arrow.triangle.2.circlepath")
            }
            .tint(.purple)
        }
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
            optimizationResult = store.optimizeShoppingList(listID, maxStoresOverride: forceOneStore ? 1 : nil)
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

    private func formatDecimal(_ d: Decimal) -> String {
        NSDecimalNumber(decimal: d).stringValue
    }
}

// MARK: - Item Row View

struct ShoppingItemRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: ShoppingListItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.isCompleted ? .green : Color(.systemGray3))
                .font(.body)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: item.isCompleted)
                .symbolEffectsRemoved(reduceMotion)
                .animation(.snappy, value: item.isCompleted)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.productName)
                    .font(.callout)
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
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

// MARK: - Needs Price Item Row

private struct NeedsPriceItemRow: View {
    let item: ShoppingListItem
    let hasCommunityPrice: Bool
    let onAddPrice: () -> Void
    let onUseCommunity: () -> Void
    let onScanBarcode: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.productName)
                    .font(.callout)
                Text(item.requestedQuantity)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button(action: onAddPrice) {
                    Label("Add Price", systemImage: "plus.circle")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if hasCommunityPrice {
                    Button(action: onUseCommunity) {
                        Label("Use Community Price", systemImage: "person.3.fill")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.purple)
                }

                Button(action: onScanBarcode) {
                    Image(systemName: "barcode.viewfinder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Scan barcode")
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Move Item To Store Sheet

struct MoveItemToStoreSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let item: ShoppingListItem
    let listID: UUID

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.enabledBranches) { branch in
                        Button {
                            store.moveItem(item.id, in: listID, toBranchID: branch.id)
                            dismiss()
                        } label: {
                            HStack {
                                Text(branch.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if item.assignedStoreBranch == branch.displayName {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Move \(item.productName) to")
                } footer: {
                    Text("Looks up the best known price for this product at the store you pick. If there's none yet, the item moves with no price.")
                }
            }
            .navigationTitle("Move Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Substitute Item Sheet

struct SubstituteItemSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let item: ShoppingListItem
    let listID: UUID

    @State private var newCandidateText = ""

    private var candidates: [String] {
        store.shoppingLists
            .first { $0.id == listID }?
            .items.first { $0.id == item.id }?
            .substituteCandidateNames ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Currently") {
                    Text(item.productName)
                }

                if !candidates.isEmpty {
                    Section("Substitute with") {
                        ForEach(candidates, id: \.self) { candidate in
                            Button {
                                store.useSubstitute(item.id, in: listID, newProductName: candidate)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(candidate)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("Use")
                                        .foregroundStyle(.blue)
                                        .font(.caption.weight(.medium))
                                }
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        TextField("e.g. store-brand mince", text: $newCandidateText)
                            .autocorrectionDisabled()
                        Button("Add") {
                            store.addSubstituteCandidate(item.id, in: listID, name: newCandidateText)
                            newCandidateText = ""
                        }
                        .disabled(newCandidateText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("New substitute idea")
                } footer: {
                    Text("Using a substitute clears this item's price and store assignment — it needs its own pricing, and the current product is kept as a substitute idea so you can switch back.")
                }
            }
            .navigationTitle("Substitute Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
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
