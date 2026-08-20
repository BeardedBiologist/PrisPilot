import SwiftUI

struct ShoppingView: View {
    @Environment(AppStore.self) private var store
    @State private var showAddList = false

    var body: some View {
        NavigationStack {
            List {
                if store.activeLists.isEmpty {
                    ContentUnavailableView(
                        "No Shopping Lists",
                        systemImage: "cart",
                        description: Text("Create a list with the + button, or ask the AI in Chat.")
                    )
                } else {
                    ForEach(store.activeLists) { list in
                        NavigationLink(destination: ShoppingListDetailView(listID: list.id)) {
                            ShoppingListRow(list: list)
                        }
                    }
                    .onDelete { indexSet in
                        let ids = indexSet.map { store.activeLists[$0].id }
                        store.shoppingLists.removeAll { ids.contains($0.id) }
                    }
                }
            }
            .navigationTitle("Shopping")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddList = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAddList) {
                AddShoppingListSheet().environment(store)
            }
        }
    }
}

struct ShoppingListRow: View {
    let list: ShoppingList
    var completedCount: Int { list.items.filter { $0.isCompleted }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(list.name).font(.headline)
            HStack {
                Text("\(list.items.count) item\(list.items.count == 1 ? "" : "s")")
                if list.items.count > 0 {
                    Text("·")
                    Text("\(completedCount) done")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Shopping List Detail

struct ShoppingListDetailView: View {
    @Environment(AppStore.self) private var store
    let listID: UUID
    @State private var showAddItem = false
    @State private var showComparison = false

    private var list: ShoppingList? { store.shoppingLists.first { $0.id == listID } }
    private var listIdx: Int? { store.shoppingLists.firstIndex { $0.id == listID } }

    var body: some View {
        List {
            if let current = list {
                let pending = current.items.filter { !$0.isCompleted }
                let done    = current.items.filter {  $0.isCompleted }

                if current.items.isEmpty {
                    ContentUnavailableView(
                        "Empty List",
                        systemImage: "cart.badge.plus",
                        description: Text("Tap + to add an item, or ask the AI in Chat.")
                    )
                } else {
                    if !pending.isEmpty {
                        Section("To buy — \(pending.count)") {
                            ForEach(pending) { item in
                                ShoppingItemRow(item: item, onToggle: { toggle(item: item) })
                            }
                            .onDelete { offsets in deleteItems(from: pending, at: offsets) }
                        }
                    }
                    if !done.isEmpty {
                        Section("Done — \(done.count)") {
                            ForEach(done) { item in
                                ShoppingItemRow(item: item, onToggle: { toggle(item: item) })
                            }
                            .onDelete { offsets in deleteItems(from: done, at: offsets) }
                        }
                    }
                }
            }
        }
        .navigationTitle(list?.name ?? "List")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    if !(list?.items.isEmpty ?? true) {
                        Button {
                            showComparison = true
                        } label: {
                            Image(systemName: "chart.bar.xaxis")
                        }
                    }
                    Button { showAddItem = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .sheet(isPresented: $showAddItem) {
            AddShoppingListItemSheet(listID: listID).environment(store)
        }
        .navigationDestination(isPresented: $showComparison) {
            if let current = list {
                PriceComparisonView(list: current).environment(store)
            }
        }
    }

    private func toggle(item: ShoppingListItem) {
        guard let idx = listIdx,
              let itemIdx = store.shoppingLists[idx].items.firstIndex(where: { $0.id == item.id }) else { return }
        store.shoppingLists[idx].items[itemIdx].isCompleted.toggle()
    }

    private func deleteItems(from items: [ShoppingListItem], at offsets: IndexSet) {
        guard let idx = listIdx else { return }
        let ids = offsets.map { items[$0].id }
        store.shoppingLists[idx].items.removeAll { ids.contains($0.id) }
    }
}

struct ShoppingItemRow: View {
    let item: ShoppingListItem
    var onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? .green : Color(.systemGray3))
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.productName)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                Text(item.requestedQuantity)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let notes = item.notes {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }

            Spacer()

            if let price = item.estimatedPrice {
                Text("kr \(NSDecimalNumber(decimal: price).stringValue)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
