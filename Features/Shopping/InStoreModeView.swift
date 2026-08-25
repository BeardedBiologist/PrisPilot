import SwiftUI
import UIKit

/// Full-screen, one-store-at-a-time shopping mode: large checkboxes, a
/// running subtotal, and a "next item" focus highlight — built for
/// glancing at the phone while your hands are full of groceries, not for
/// reading. Reuses the same completion/price-capture plumbing as the
/// normal list detail view rather than duplicating it.
struct InStoreModeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let listID: UUID
    let initialStore: String

    @State private var selectedStore: String
    @State private var itemForPriceCapture: ShoppingListItem?
    @State private var showNextStorePrompt = false

    init(listID: UUID, initialStore: String) {
        self.listID = listID
        self.initialStore = initialStore
        _selectedStore = State(initialValue: initialStore)
    }

    private var list: ShoppingList? { store.shoppingLists.first { $0.id == listID } }
    private var listIdx: Int? { store.shoppingLists.firstIndex { $0.id == listID } }

    /// Stores with at least one priced item, in a stable order — the set
    /// this mode can page between.
    private var storesInTrip: [String] {
        let names = Set((list?.items ?? []).compactMap { $0.estimatedPrice != nil ? $0.assignedStoreBranch : nil })
        return names.sorted()
    }

    private var itemsForSelectedStore: [ShoppingListItem] {
        (list?.items ?? []).filter { $0.assignedStoreBranch == selectedStore && $0.estimatedPrice != nil }
    }

    private var pendingItems: [ShoppingListItem] { itemsForSelectedStore.filter { !$0.isCompleted } }
    private var doneItems: [ShoppingListItem] { itemsForSelectedStore.filter { $0.isCompleted } }
    private var nextFocusItemID: UUID? { pendingItems.first?.id }

    private var subtotal: Decimal {
        itemsForSelectedStore.compactMap(\.estimatedPrice).reduce(0, +)
    }
    private var spentSoFar: Decimal {
        doneItems.compactMap { $0.actualPrice ?? $0.estimatedPrice }.reduce(0, +)
    }

    private var nextStoreWithPendingItems: String? {
        storesInTrip.first { storeName in
            storeName != selectedStore &&
            (list?.items.contains { $0.assignedStoreBranch == storeName && $0.estimatedPrice != nil && !$0.isCompleted } ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        if storesInTrip.count > 1 {
                            Picker("Store", selection: $selectedStore) {
                                ForEach(storesInTrip, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }

                        HStack(alignment: .lastTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("kr \(formatDecimal(spentSoFar))")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .contentTransition(.numericText())
                                    .animation(reduceMotion ? nil : .snappy, value: spentSoFar)
                                Text("of kr \(formatDecimal(subtotal)) at \(selectedStore)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(doneItems.count)/\(itemsForSelectedStore.count)")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        ProgressView(value: Double(doneItems.count), total: Double(max(itemsForSelectedStore.count, 1)))
                            .tint(.green)
                    }
                    .padding(.vertical, 4)
                }

                if pendingItems.isEmpty && !itemsForSelectedStore.isEmpty {
                    Section {
                        Label("This store is done!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.headline)
                        if let next = nextStoreWithPendingItems {
                            Button {
                                withAnimation(reduceMotion ? nil : .snappy) { selectedStore = next }
                            } label: {
                                Label("Continue to \(next)", systemImage: "arrow.right.circle.fill")
                            }
                        }
                    }
                }

                if !pendingItems.isEmpty {
                    Section("To Buy") {
                        ForEach(pendingItems) { item in
                            inStoreRow(item, isNextFocus: item.id == nextFocusItemID)
                        }
                    }
                }

                if !doneItems.isEmpty {
                    Section("In Cart") {
                        ForEach(doneItems) { item in
                            inStoreRow(item, isNextFocus: false)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("In-Store Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $itemForPriceCapture) { item in
                PriceCaptureSheet(item: item) { price in
                    captureActualPrice(for: item.id, price: price)
                }
                .environment(store)
            }
            .onChange(of: pendingItems.count) { oldCount, newCount in
                if oldCount > 0 && newCount == 0 && nextStoreWithPendingItems != nil {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
    }

    @ViewBuilder
    private func inStoreRow(_ item: ShoppingListItem, isNextFocus: Bool) -> some View {
        Button {
            toggle(item: item)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 32))
                    .foregroundStyle(item.isCompleted ? .green : (isNextFocus ? .blue : Color(.systemGray3)))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: item.isCompleted)
                    .symbolEffectsRemoved(reduceMotion)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.productName)
                        .font(isNextFocus ? .title3.weight(.semibold) : .body)
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    Text(item.requestedQuantity)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let price = item.actualPrice ?? item.estimatedPrice {
                    Text("kr \(formatDecimal(price))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, isNextFocus ? 8 : 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(isNextFocus ? Color.blue.opacity(0.08) : nil)
    }

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
