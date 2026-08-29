import SwiftUI

// MARK: - Shopping Tab Root

struct ShoppingView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.switchToChatTab) private var switchToChatTab
    @State private var showAddList = false
    @State private var segment: ShoppingListSegment = .active
    @State private var isOptimizingAll = false
    @Namespace private var heroSpace

    private var listsForSegment: [ShoppingList] {
        switch segment {
        case .active: return store.activeLists
        case .planned: return store.plannedLists
        case .archived: return store.archivedLists + store.completedLists
        }
    }

    private var personalLists: [ShoppingList] {
        listsForSegment.filter { $0.scope == .personal }
    }

    private var householdLists: [ShoppingList] {
        listsForSegment.filter { $0.scope == .household }
    }

    // MARK: Header summary (always computed from Active + Planned, regardless of selected segment)

    private var nextPlannedDate: Date? {
        (store.activeLists + store.plannedLists)
            .compactMap(\.plannedDate)
            .filter { $0 >= Calendar.current.startOfDay(for: Date()) }
            .min()
    }

    private var activeEstimatedSpend: Decimal {
        store.activeLists.reduce(Decimal.zero) { total, list in
            total + list.items.filter { !$0.isCompleted }.compactMap(\.estimatedPrice).reduce(0, +)
        }
    }

    private var activeMissingPriceCount: Int {
        store.activeLists.reduce(0) { total, list in
            total + list.items.filter { !$0.isCompleted && $0.estimatedPrice == nil }.count
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ShoppingSummaryHeader(
                        activeCount: store.activeLists.count,
                        nextPlannedDate: nextPlannedDate,
                        estimatedSpend: activeEstimatedSpend,
                        missingPriceCount: activeMissingPriceCount
                    )
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                .listRowSeparator(.hidden)

                Section {
                    Picker("View", selection: $segment) {
                        ForEach(ShoppingListSegment.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)

                Section {
                    ShoppingPrimaryActionsRow(
                        showOptimizeAll: segment == .active && !store.activeLists.isEmpty && !store.enabledBranches.isEmpty,
                        isOptimizingAll: isOptimizingAll,
                        onNewList: { showAddList = true },
                        onOptimizeAll: optimizeAllActiveLists,
                        onAskAI: { switchToChatTab() }
                    )
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)

                if listsForSegment.isEmpty {
                    ContentUnavailableView(
                        segment.emptyTitle,
                        systemImage: segment.emptySystemImage,
                        description: Text(segment.emptyDescription)
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
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
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
        switch list.status {
        case .planned:
            Button { store.activateList(list.id) } label: {
                Label("Start Shopping", systemImage: "cart")
            }
        case .active:
            Button { store.archiveShoppingList(list.id) } label: {
                Label("Archive", systemImage: "archivebox")
            }
        case .completed, .archived:
            Button { store.reopenList(list.id) } label: {
                Label("Reopen", systemImage: "arrow.uturn.backward")
            }
        }

        Button(role: .destructive) {
            store.shoppingLists.removeAll { $0.id == list.id }
            store.persistNow()
        } label: {
            Label("Delete List", systemImage: "trash")
        }
    }

    private func optimizeAllActiveLists() {
        isOptimizingAll = true
        Task { @MainActor in
            for list in store.activeLists {
                store.optimizeShoppingList(list.id)
            }
            isOptimizingAll = false
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

    private var missingPriceCount: Int {
        list.items.filter { !$0.isCompleted && $0.estimatedPrice == nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            mainRow
            if showsBadgeRow {
                badgeRow
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    private var showsBadgeRow: Bool {
        list.plannedDate != nil || list.optimizationSnapshot != nil || missingPriceCount > 0
    }

    private var mainRow: some View {
        HStack(alignment: .center, spacing: 12) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(progress == 1 ? Color.green : Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy, value: progress)
                Text("\(done)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(progress == 1 ? .green : .primary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: done)
            }
            .frame(width: 36, height: 36)

            // Name and subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(total == 0 ? "Empty" : "\(total) item\(total == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Total
            VStack(alignment: .trailing, spacing: 1) {
                if let total = estimatedTotal {
                    Text("kr \(formatDecimal(total))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: total)
                    Text("est.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if total == 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Color(.systemGray3))
                } else {
                    Text("No prices")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var badgeRow: some View {
        HStack(spacing: 6) {
            if let plannedDate = list.plannedDate {
                badge(
                    text: plannedDate.formatted(.relative(presentation: .named)),
                    systemImage: "calendar",
                    color: .purple
                )
            }

            if let snapshot = list.optimizationSnapshot {
                if snapshot.chosenStores.count > 1 {
                    badge(text: "\(snapshot.chosenStores.count) stores", systemImage: "storefront", color: .blue)
                } else if let store = snapshot.chosenStores.first {
                    badge(text: store, systemImage: "storefront", color: .blue)
                }
                if snapshot.savings > 0 {
                    badge(text: "Saves kr \(formatDecimal(snapshot.savings))", systemImage: "arrow.down.circle.fill", color: .green)
                }
            }

            if missingPriceCount > 0 {
                badge(text: "\(missingPriceCount) need\(missingPriceCount == 1 ? "s" : "") price", systemImage: "exclamationmark.circle.fill", color: .orange)
            }

            Spacer(minLength: 0)
        }
    }

    private func badge(text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func formatDecimal(_ d: Decimal) -> String {
        NSDecimalNumber(decimal: d).stringValue
    }
}
