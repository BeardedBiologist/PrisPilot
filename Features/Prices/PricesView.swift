import SwiftUI

private struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
    init(_ value: String) { self.value = value }
}

// MARK: - View Mode

private enum PriceViewMode: String, CaseIterable {
    case byProduct = "Products"
    case byStore = "Stores"
    case needsPrices = "Needs Prices"
    case community = "Community"
}

// MARK: - Prices View

struct PricesView: View {
    @Environment(AppStore.self) private var store
    @State private var showAddPrice = false
    @State private var showBarcodeScanner = false
    @State private var showReceiptScanner = false
    @State private var searchText = ""
    @State private var viewMode: PriceViewMode = .byProduct
    @State private var selectedProductName: IdentifiableString? = nil
    @State private var productNameForNewPrice: IdentifiableString? = nil
    @State private var selectedBranch: StoreBranch? = nil

    private var filtered: [PriceObservation] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.priceObservations }
        return store.priceObservations.filter {
            $0.productName.lowercased().contains(q) ||
            $0.storeBranchName.lowercased().contains(q)
        }
    }

    // MARK: Needs Prices

    private var allNeedsPriceEntries: [AppStore.NeedsPriceEntry] {
        store.needsPriceEntries()
    }

    private var filteredNeedsPriceEntries: [AppStore.NeedsPriceEntry] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return allNeedsPriceEntries }
        return allNeedsPriceEntries.filter { $0.productName.lowercased().contains(q) }
    }

    // MARK: Community

    private var allCommunityObservations: [PriceObservation] {
        store.priceObservations.filter { $0.source == .community }
    }

    private var filteredCommunityObservations: [PriceObservation] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return allCommunityObservations }
        return allCommunityObservations.filter {
            $0.productName.lowercased().contains(q) ||
            $0.storeBranchName.lowercased().contains(q)
        }
    }

    private var groupedByProduct: [(key: String, value: [PriceObservation])] {
        let grouped = Dictionary(grouping: filtered, by: { $0.productName })
        return grouped.map { (key: $0.key, value: $0.value.sorted { $0.observedDate > $1.observedDate }) }
            .sorted { $0.key < $1.key }
    }

    private var groupedByStore: [(key: String, value: [PriceObservation])] {
        let grouped = Dictionary(grouping: filtered, by: { $0.storeBranchName })
        return grouped.map { (key: $0.key, value: $0.value.sorted { $0.productName < $1.productName }) }
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack {
            List {
                if !store.enabledBranches.isEmpty || !store.priceObservations.isEmpty {
                    modePickerRow
                    summaryRow
                }

                if store.priceObservations.isEmpty && store.enabledBranches.isEmpty {
                    ContentUnavailableView(
                        "No Price Data Yet",
                        systemImage: "tag",
                        description: Text("Tell me in Chat what you paid for items and I'll record prices automatically.")
                    )
                } else {
                    switch viewMode {
                    case .byProduct:
                        if store.priceObservations.isEmpty {
                            ContentUnavailableView(
                                "No Prices Recorded",
                                systemImage: "tag",
                                description: Text("You have \(store.enabledBranches.count) store\(store.enabledBranches.count == 1 ? "" : "s") set up. Tap + to add your first price, or tell me in Chat.")
                            )
                        } else if filtered.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        } else {
                            productSections
                        }
                    case .byStore:
                        storeSections
                    case .needsPrices:
                        if allNeedsPriceEntries.isEmpty {
                            ContentUnavailableView(
                                "Nothing Needs Prices",
                                systemImage: "checkmark.circle",
                                description: Text("Every item on your active lists and every recipe ingredient has a recent price.")
                            )
                        } else if filteredNeedsPriceEntries.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        } else {
                            needsPriceSection
                        }
                    case .community:
                        if allCommunityObservations.isEmpty {
                            ContentUnavailableView(
                                "No Community Prices Yet",
                                systemImage: "person.3",
                                description: Text("Community-sourced prices will show up here once they're available for your area.")
                            )
                        } else if filteredCommunityObservations.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        } else {
                            communitySections
                        }
                    }
                }
            }
            .reservesFloatingTabBarSpace()
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search products or stores"
            )
            .navigationTitle("Prices")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button { showReceiptScanner = true } label: { Image(systemName: "doc.viewfinder") }
                            .accessibilityLabel("Scan receipt")
                        Button { showBarcodeScanner = true } label: { Image(systemName: "barcode.viewfinder") }
                            .accessibilityLabel("Scan barcode")
                        Button { showAddPrice = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Add price")
                    }
                }
            }
            .sheet(isPresented: $showAddPrice) {
                AddPriceObservationSheet().environment(store)
            }
            .sheet(isPresented: $showBarcodeScanner) {
                BarcodeScannerView(mode: .priceEntry).environment(store)
            }
            .sheet(isPresented: $showReceiptScanner) {
                ReceiptScannerView().environment(store)
            }
            .sheet(item: $selectedProductName) { item in
                ProductPriceHistoryView(productName: item.value)
                    .environment(store)
            }
            .sheet(item: $productNameForNewPrice) { item in
                AddPriceObservationSheet(prefilledProductName: item.value)
                    .environment(store)
            }
            .sheet(item: $selectedBranch) { branch in
                StoreDetailView(branch: branch).environment(store)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var productSections: some View {
        ForEach(groupedByProduct, id: \.key) { group in
            Section {
                let cheapestID = cheapestObservationID(in: group.value)
                ForEach(group.value) { obs in
                    PriceObservationRow(
                        observation: obs,
                        communityConfidence: obs.source == .community ? store.communityConfidence(for: obs) : nil,
                        isCommunityOutlier: obs.source == .community && store.isOutlier(obs),
                        isCheapest: obs.id == cheapestID && group.value.count > 1
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selectedProductName = IdentifiableString(group.key) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if obs.source == .community {
                            Button { store.flagCommunityPriceObservation(obs.id) } label: {
                                Label("Flag", systemImage: "flag")
                            }
                            .tint(.orange)
                        }
                    }
                }
            } header: {
                Button {
                    selectedProductName = IdentifiableString(group.key)
                } label: {
                    HStack {
                        Text(group.key)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                }
                .foregroundStyle(.primary)
            }
        }
    }

    @ViewBuilder
    private var storeSections: some View {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let visibleBranches = store.enabledBranches.filter {
            q.isEmpty || $0.displayName.lowercased().contains(q)
        }
        ForEach(visibleBranches) { branch in
            let branchObs = store.priceObservations
                .filter { $0.storeBranchID == branch.id && (q.isEmpty || $0.productName.lowercased().contains(q)) }
                .sorted { $0.productName < $1.productName }
            Section {
                if branchObs.isEmpty {
                    Text("No prices recorded here yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(branchObs) { obs in
                        StoreModeRow(observation: obs)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedProductName = IdentifiableString(obs.productName) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if obs.source == .community {
                                    Button { store.flagCommunityPriceObservation(obs.id) } label: {
                                        Label("Flag", systemImage: "flag")
                                    }
                                    .tint(.orange)
                                }
                            }
                    }
                }
            } header: {
                Button {
                    selectedBranch = branch
                } label: {
                    HStack {
                        Text(branch.displayName)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                }
                .foregroundStyle(.primary)
            }
        }
    }

    @ViewBuilder
    private var needsPriceSection: some View {
        Section {
            ForEach(filteredNeedsPriceEntries) { entry in
                NeedsPriceRow(entry: entry) {
                    productNameForNewPrice = IdentifiableString(entry.productName)
                }
            }
        } header: {
            Text("\(filteredNeedsPriceEntries.count) product\(filteredNeedsPriceEntries.count == 1 ? "" : "s") need\(filteredNeedsPriceEntries.count == 1 ? "s" : "") a price")
        }
    }

    @ViewBuilder
    private var communitySections: some View {
        let grouped = Dictionary(grouping: filteredCommunityObservations, by: { $0.productName })
        ForEach(grouped.keys.sorted(), id: \.self) { productName in
            Section(productName) {
                ForEach((grouped[productName] ?? []).sorted { $0.observedDate > $1.observedDate }) { obs in
                    PriceObservationRow(
                        observation: obs,
                        communityConfidence: store.communityConfidence(for: obs),
                        isCommunityOutlier: store.isOutlier(obs),
                        matchesPersonalPrice: personalPriceMatch(for: obs)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selectedProductName = IdentifiableString(productName) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button { store.flagCommunityPriceObservation(obs.id) } label: {
                            Label("Flag", systemImage: "flag")
                        }
                        .tint(.orange)
                    }
                }
            }
        }
    }

    /// `true`/`false` when a non-stale personal observation exists for the
    /// same product at the same store (matches or differs in price);
    /// `nil` when there's nothing personal to compare against.
    private func personalPriceMatch(for observation: PriceObservation) -> Bool? {
        guard let personal = store.priceObservations.first(where: {
            $0.source != .community &&
            $0.productID == observation.productID &&
            $0.storeBranchID == observation.storeBranchID &&
            !$0.isStale &&
            !$0.isPromoExpired
        }) else { return nil }
        return personal.price == observation.price
    }

    // MARK: - Summary & Mode Picker

    private var modePickerRow: some View {
        Section {
            Picker("View", selection: $viewMode) {
                ForEach(PriceViewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 0, trailing: 16))
    }

    private var summaryRow: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    statTile(value: "\(uniqueProductCount)", label: "products", icon: "shoppingbag.fill", color: .blue)
                    statTile(value: "\(uniqueStoreCount)", label: "stores", icon: "building.2.fill", color: .green)
                    if staleCount > 0 {
                        statTile(value: "\(staleCount)", label: "stale", icon: "clock.fill", color: .orange)
                    }
                    if !allNeedsPriceEntries.isEmpty {
                        statTile(value: "\(allNeedsPriceEntries.count)", label: "need price", icon: "questionmark.circle.fill", color: .red)
                    }
                    if !allCommunityObservations.isEmpty {
                        statTile(value: "\(uniqueCommunityProductCount)", label: "community", icon: "person.3.fill", color: .purple)
                    }
                    if let lastDate = lastObservedDate {
                        statTile(
                            value: lastDate.formatted(.relative(presentation: .named)),
                            label: "last update",
                            icon: "calendar",
                            color: Color(.secondaryLabel)
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 4, trailing: 12))
    }

    private func statTile(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 70, height: 56)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Helpers

    private var uniqueProductCount: Int { Set(store.priceObservations.map { $0.productName }).count }
    private var uniqueStoreCount: Int { store.enabledBranches.count }
    private var staleCount: Int { store.priceObservations.filter { $0.isStale }.count }
    private var lastObservedDate: Date? { store.priceObservations.map { $0.observedDate }.max() }
    private var uniqueCommunityProductCount: Int { Set(allCommunityObservations.map { $0.productName }).count }

    private func cheapestObservationID(in group: [PriceObservation]) -> UUID? {
        var latestByStore: [UUID: PriceObservation] = [:]
        for obs in group where !obs.isPromoExpired {
            if let existing = latestByStore[obs.storeBranchID] {
                if obs.observedDate > existing.observedDate { latestByStore[obs.storeBranchID] = obs }
            } else {
                latestByStore[obs.storeBranchID] = obs
            }
        }
        return latestByStore.values.min(by: { $0.price < $1.price })?.id
    }
}

// MARK: - Product Price History

struct ProductPriceHistoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let productName: String

    @State private var newAliasText = ""
    @State private var showMergeSheet = false

    private var observations: [PriceObservation] {
        store.priceObservations
            .filter { $0.productName == productName }
            .sorted { $0.observedDate > $1.observedDate }
    }

    private var personalObservations: [PriceObservation] { observations.filter { $0.source != .community } }
    private var communityObservations: [PriceObservation] { observations.filter { $0.source == .community } }

    private var product: Product? {
        store.products.first { $0.name.lowercased() == productName.lowercased() }
    }

    private var cheapestID: UUID? {
        var latestByStore: [UUID: PriceObservation] = [:]
        for obs in observations where !obs.isPromoExpired {
            if let existing = latestByStore[obs.storeBranchID] {
                if obs.observedDate > existing.observedDate { latestByStore[obs.storeBranchID] = obs }
            } else {
                latestByStore[obs.storeBranchID] = obs
            }
        }
        return latestByStore.values.min(by: { $0.price < $1.price })?.id
    }

    /// Latest, non-expired observation per store with a normalized unit
    /// price — lets "which store is cheapest per kg/l/stk" be compared
    /// even when package sizes differ, not just sticker price.
    private var unitPriceComparison: [(storeName: String, unitPrice: UnitPrice)] {
        var latestByStore: [UUID: PriceObservation] = [:]
        for obs in observations where !obs.isPromoExpired {
            if let existing = latestByStore[obs.storeBranchID] {
                if obs.observedDate > existing.observedDate { latestByStore[obs.storeBranchID] = obs }
            } else {
                latestByStore[obs.storeBranchID] = obs
            }
        }
        return latestByStore.values
            .compactMap { obs in obs.normalizedUnitPrice.map { (obs.storeBranchName, $0) } }
            .sorted { $0.unitPrice.value < $1.unitPrice.value }
    }

    private var priceRange: String? {
        guard observations.count > 1 else { return nil }
        let prices = observations.map { $0.price }
        guard let lo = prices.min(), let hi = prices.max(), lo != hi else { return nil }
        let sym = observations.first?.currency.symbol ?? "kr"
        return "\(sym) \(NSDecimalNumber(decimal: lo).stringValue) – \(sym) \(NSDecimalNumber(decimal: hi).stringValue)"
    }

    var body: some View {
        NavigationStack {
            List {
                if let cheapest = observations.first(where: { $0.id == cheapestID }) {
                    Section("Best current price") {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(cheapest.storeBranchName)
                                    .font(.subheadline.weight(.medium))
                                Text(cheapest.observedDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Label(
                                "\(cheapest.currency.symbol) \(NSDecimalNumber(decimal: cheapest.price).stringValue)",
                                systemImage: "checkmark.seal.fill"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                        }
                        .padding(.vertical, 2)
                    }
                }

                if unitPriceComparison.count > 1 {
                    Section {
                        ForEach(Array(unitPriceComparison.enumerated()), id: \.offset) { index, entry in
                            HStack {
                                Text(entry.storeName)
                                    .font(.subheadline)
                                if index == 0 {
                                    Text("CHEAPEST")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(.green, in: Capsule())
                                }
                                Spacer()
                                Text(entry.unitPrice.formatted(currencySymbol: store.settings.currency.symbol))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(index == 0 ? .green : .primary)
                            }
                        }
                    } header: {
                        Text("Unit Price Comparison")
                    } footer: {
                        Text("Normalized to a common unit so differently-sized packages compare fairly.")
                    }
                }

                if !personalObservations.isEmpty {
                    Section("Your Prices (\(personalObservations.count))") {
                        ForEach(personalObservations) { obs in
                            PriceObservationRow(
                                observation: obs,
                                isCheapest: obs.id == cheapestID && observations.count > 1
                            )
                        }
                    }
                }

                if !communityObservations.isEmpty {
                    Section("Community Prices (\(communityObservations.count))") {
                        ForEach(communityObservations) { obs in
                            PriceObservationRow(
                                observation: obs,
                                communityConfidence: store.communityConfidence(for: obs),
                                isCommunityOutlier: store.isOutlier(obs),
                                isCheapest: obs.id == cheapestID && observations.count > 1
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button { store.flagCommunityPriceObservation(obs.id) } label: {
                                    Label("Flag", systemImage: "flag")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }

                if observations.count > 1 {
                    Section("Summary") {
                        LabeledContent("Observations", value: "\(observations.count)")
                        if let range = priceRange {
                            LabeledContent("Price range", value: range)
                        }
                        if let oldest = observations.last {
                            LabeledContent("First recorded", value: oldest.observedDate.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                }

                if let product {
                    Section("Barcode") {
                        TextField(
                            "No barcode saved",
                            text: Binding(
                                get: { product.barcode ?? "" },
                                set: { store.setProductBarcode(product.id, barcode: $0.isEmpty ? nil : $0) }
                            )
                        )
                        .keyboardType(.numberPad)
                    }

                    Section {
                        ForEach(product.aliases, id: \.self) { alias in
                            Text(alias)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                store.removeProductAlias(product.id, alias: product.aliases[index])
                            }
                        }
                        HStack {
                            TextField("Add alias (e.g. store-specific name)", text: $newAliasText)
                                .autocorrectionDisabled()
                            Button("Add") {
                                store.addProductAlias(product.id, alias: newAliasText)
                                newAliasText = ""
                            }
                            .disabled(newAliasText.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } header: {
                        Text("Aliases")
                    } footer: {
                        Text("Alternate names this product is known by across stores or receipts.")
                    }

                    Section {
                        Button {
                            showMergeSheet = true
                        } label: {
                            Label("Merge Duplicate Product", systemImage: "arrow.triangle.merge")
                        }
                    }
                }
            }
            .navigationTitle(productName)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showMergeSheet) {
                if let product {
                    MergeProductSheet(targetProduct: product).environment(store)
                }
            }
        }
    }
}

// MARK: - Merge Product Sheet

struct MergeProductSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let targetProduct: Product

    private var candidates: [Product] {
        store.products.filter { $0.id != targetProduct.id }.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        "No Other Products",
                        systemImage: "tag",
                        description: Text("There's nothing else to merge yet.")
                    )
                } else {
                    Section {
                        ForEach(candidates) { candidate in
                            Button {
                                store.mergeProducts(sourceID: candidate.id, targetID: targetProduct.id)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(candidate.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "arrow.triangle.merge")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Merge into \"\(targetProduct.name)\"")
                    } footer: {
                        Text("The selected product's prices and aliases move to \(targetProduct.name), and the duplicate is deleted. This can't be undone.")
                    }
                }
            }
            .navigationTitle("Merge Duplicate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Store Mode Row

private struct StoreModeRow: View {
    let observation: PriceObservation

    private var priceText: String {
        "\(observation.currency.symbol) \(NSDecimalNumber(decimal: observation.price).stringValue)"
    }
    private var quantityText: String? {
        guard let qty = observation.quantity else { return nil }
        let unit = observation.unit?.rawValue ?? ""
        return "\(qty.formatted()) \(unit)"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(observation.productName)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 4) {
                    if let qty = quantityText {
                        Text(qty)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                    Text(observation.observedDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if observation.isStale {
                    Label("Stale", systemImage: "clock.fill")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                } else if observation.isPromotion && !observation.isPromoExpired {
                    Label("Offer", systemImage: "tag.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Text(priceText)
                .font(.subheadline.weight(.semibold))
                .contentTransition(.numericText())
                .animation(.snappy, value: observation.price)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Price Observation Row

struct PriceObservationRow: View {
    let observation: PriceObservation
    var communityConfidence: PriceConfidence?
    var isCommunityOutlier: Bool = false
    var isCheapest: Bool = false
    /// `true`/`false` when there's a personal price at the same product +
    /// store to compare against (Community mode); `nil` when there's
    /// nothing to compare, in which case nothing extra is shown.
    var matchesPersonalPrice: Bool? = nil

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
                if let priceKind = observation.priceKind, priceKind != .regular {
                    Label(priceKind.rawValue, systemImage: priceKind == .member ? "person.crop.circle.fill" : "star.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                if observation.source == .community {
                    Label("Community", systemImage: "person.3.fill")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                }
                Text(observation.observedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(Color(.tertiaryLabel))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(priceText)
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: observation.price)
                if isCheapest {
                    Label("Best price", systemImage: "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                statusBadge
                if isCommunityOutlier {
                    Label("Outlier", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                if let matchesPersonalPrice {
                    Label(
                        matchesPersonalPrice ? "Confirms your price" : "Differs from your price",
                        systemImage: matchesPersonalPrice ? "checkmark.seal.fill" : "arrow.left.arrow.right.circle.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(matchesPersonalPrice ? .green : .blue)
                }
                confidencePill
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if observation.isPromoExpired {
            Label("Expired", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        } else if observation.isPromotion {
            Label(promotionText, systemImage: "tag.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
        } else if observation.isStale {
            Label("Stale", systemImage: "clock.fill")
                .font(.caption2)
                .foregroundStyle(.gray)
        }
    }

    private var promotionText: String {
        guard let endDate = observation.promotionEndDate else { return "Offer" }
        return "Offer until \(endDate.formatted(date: .abbreviated, time: .omitted))"
    }

    private var confidencePill: some View {
        Text(confidenceText)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(confidenceColor.opacity(0.15), in: Capsule())
            .foregroundStyle(confidenceColor)
    }

    private var confidenceColor: Color {
        switch communityConfidence ?? observation.freshnessAdjustedConfidence {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .orange
        case .unconfirmed: return .gray
        }
    }

    private var confidenceText: String {
        let adjusted = communityConfidence ?? observation.freshnessAdjustedConfidence
        if adjusted == observation.confidence {
            return adjusted.rawValue
        }
        return "\(adjusted.rawValue) freshness"
    }
}

// MARK: - Needs Price Row

private struct NeedsPriceRow: View {
    let entry: AppStore.NeedsPriceEntry
    let onAddPrice: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.productName)
                    .font(.subheadline.weight(.medium))
                Text(entry.sources.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Add Price", action: onAddPrice)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 3)
    }
}
