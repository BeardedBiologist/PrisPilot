import SwiftUI

// MARK: - Add Shopping List

struct AddShoppingListSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var scope: DataScope = .personal
    @State private var hasPlannedDate = false
    @State private var plannedDate = Date().addingTimeInterval(86400)

    var body: some View {
        NavigationStack {
            Form {
                Section("List name") {
                    TextField("e.g. Weekly Shop, Taco Night", text: $name)
                        .autocorrectionDisabled()
                }
                if store.household != nil {
                    Section("Scope") {
                        Picker("Scope", selection: $scope) {
                            Text("Personal").tag(DataScope.personal)
                            Text("Household").tag(DataScope.household)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section {
                    Toggle("Set a planned date", isOn: $hasPlannedDate.animation())
                    if hasPlannedDate {
                        DatePicker("Shopping date", selection: $plannedDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        var list = ShoppingList(name: trimmed, scope: scope)
                        if hasPlannedDate { list.plannedDate = plannedDate }
                        store.shoppingLists.append(list)
                        store.persistNow()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Add Shopping List Item

struct AddShoppingListItemSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let listID: UUID

    @State private var productName = ""
    @State private var quantityNumber = "1"
    @State private var quantityUnit = "stk"
    @State private var preferredVariant = ""
    @State private var notes = ""
    @State private var showSuggestions = false
    @State private var selectedBranchID: UUID? = nil
    @State private var estimatedPriceText = ""

    private var listName: String {
        store.shoppingLists.first { $0.id == listID }?.name ?? "List"
    }

    private var suggestions: [Product] {
        let trimmed = productName.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }
        let lower = trimmed.lowercased()
        return store.products
            .filter { $0.name.lowercased().contains(lower) }
            .sorted { $0.name < $1.name }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Product name", text: $productName)
                        .autocorrectionDisabled()
                        .onChange(of: productName) { _, _ in
                            showSuggestions = !suggestions.isEmpty
                        }

                    if showSuggestions {
                        ForEach(suggestions) { product in
                            Button {
                                productName = product.name
                                if let variant = product.category { preferredVariant = variant }
                                showSuggestions = false
                            } label: {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                    Text(product.name)
                                        .foregroundStyle(.primary)
                                    if let cat = product.category {
                                        Text(cat)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    HStack {
                        TextField("Amount", text: $quantityNumber)
                            .keyboardType(.decimalPad)
                            .frame(maxWidth: 80)
                        Divider()
                        Picker("Unit", selection: $quantityUnit) {
                            ForEach(["stk", "pakke", "pose", "boks", "g", "kg", "mL", "L"], id: \.self) {
                                Text($0)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    TextField("Preferred variant (optional)", text: $preferredVariant)
                        .foregroundStyle(.secondary)
                }

                Section("Store") {
                    if store.enabledBranches.isEmpty {
                        Text("No stores saved yet — add one in the Prices tab.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Buy at", selection: $selectedBranchID) {
                            Text("Auto-assign").tag(Optional<UUID>.none)
                            ForEach(store.enabledBranches) { branch in
                                Text(branch.displayName).tag(Optional(branch.id))
                            }
                        }
                    }
                }

                Section("Price") {
                    HStack {
                        Text("kr")
                            .foregroundStyle(.secondary)
                        TextField("Estimated price (optional)", text: $estimatedPriceText)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("Notes") {
                    TextField("Add a note (optional)", text: $notes)
                }
            }
            .navigationTitle("Add to \(listName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addItem()
                        dismiss()
                    }
                    .disabled(productName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addItem() {
        guard let idx = store.shoppingLists.firstIndex(where: { $0.id == listID }) else { return }
        let trimmedName = productName.trimmingCharacters(in: .whitespaces)
        var item = ShoppingListItem(
            listID: listID,
            productName: trimmedName,
            requestedQuantity: quantityNumber.trimmingCharacters(in: .whitespaces).isEmpty ? "1 stk" : "\(quantityNumber.trimmingCharacters(in: .whitespaces)) \(quantityUnit)"
        )
        let trimmedVariant = preferredVariant.trimmingCharacters(in: .whitespaces)
        if !trimmedVariant.isEmpty { item.preferredVariant = trimmedVariant }
        if !notes.isEmpty { item.notes = notes.trimmingCharacters(in: .whitespaces) }

        if let branchID = selectedBranchID,
           let branch = store.enabledBranches.first(where: { $0.id == branchID }) {
            item.assignedStoreBranch = branch.displayName
        }
        let normalizedPrice = estimatedPriceText.replacingOccurrences(of: ",", with: ".")
        if let price = Decimal(string: normalizedPrice), price > 0 {
            item.estimatedPrice = price
        }

        // Link to known product if found
        item.productID = store.products.first { $0.name.lowercased() == trimmedName.lowercased() }?.id

        store.shoppingLists[idx].items.append(item)
        store.persistNow()
    }
}

// MARK: - Add Price Observation

struct AddPriceObservationSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var prefilledProductName: String? = nil
    var prefilledBarcode: String? = nil

    @State private var productName = ""
    @State private var selectedBranchID: UUID? = nil
    @State private var priceText = ""
    @State private var quantityText = ""
    @State private var selectedUnit: MeasurementUnit = .grams
    @State private var isPromotion = false
    @State private var priceKind: PriceKind = .regular
    @State private var promotionEndDate = Date().addingTimeInterval(7 * 24 * 3600)
    @State private var observedDate = Date()
    @State private var showsQuantity = false
    @State private var showAddStore = false
    @State private var newStoreName = ""
    @State private var newBranchName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Product") {
                    TextField("Product name", text: $productName)
                        .autocorrectionDisabled()
                }

                Section {
                    if !store.enabledBranches.isEmpty {
                        Picker("Branch", selection: $selectedBranchID) {
                            Text("Select store").tag(Optional<UUID>.none)
                            ForEach(store.enabledBranches) { branch in
                                Text(branch.displayName).tag(Optional(branch.id))
                            }
                        }
                    }

                    if showAddStore {
                        TextField("Store name (e.g. Kiwi)", text: $newStoreName)
                            .autocorrectionDisabled()
                        TextField("Branch / location (e.g. Majorstuen)", text: $newBranchName)
                            .autocorrectionDisabled()
                        Button("Add store") {
                            addNewStore()
                        }
                        .disabled(newStoreName.trimmingCharacters(in: .whitespaces).isEmpty)

                        Button("Cancel") {
                            showAddStore = false
                            newStoreName = ""
                            newBranchName = ""
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        Button {
                            showAddStore = true
                        } label: {
                            Label(
                                store.enabledBranches.isEmpty ? "Add a store to get started" : "Add new store",
                                systemImage: "plus"
                            )
                        }
                    }
                } header: {
                    Text("Store")
                } footer: {
                    if store.enabledBranches.isEmpty && !showAddStore {
                        Text("You need at least one store before saving a price.")
                    }
                }

                Section("Price") {
                    HStack {
                        Text("kr").foregroundStyle(.secondary)
                        TextField("0.00", text: $priceText)
                            .keyboardType(.decimalPad)
                    }
                    Toggle("Include package size", isOn: $showsQuantity.animation())
                    if showsQuantity {
                        HStack {
                            TextField("Qty (e.g. 400)", text: $quantityText)
                                .keyboardType(.decimalPad)
                            Picker("Unit", selection: $selectedUnit) {
                                ForEach(MeasurementUnit.allCases) { unit in
                                    Text(unit.rawValue).tag(unit)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    Toggle("Promotional / offer price", isOn: $isPromotion)
                    Picker("Price type", selection: $priceKind) {
                        ForEach(PriceKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    if isPromotion {
                        DatePicker("Offer ends", selection: $promotionEndDate, displayedComponents: .date)
                    }
                    DatePicker("Observed on", selection: $observedDate, displayedComponents: .date)
                }
            }
            .navigationTitle("Add Price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if selectedBranchID == nil {
                    selectedBranchID = store.enabledBranches.first?.id
                }
                if let prefilled = prefilledProductName, !prefilled.isEmpty {
                    productName = prefilled
                }
                if store.enabledBranches.isEmpty {
                    showAddStore = true
                }
            }
        }
    }

    private var isValid: Bool {
        !productName.trimmingCharacters(in: .whitespaces).isEmpty &&
        selectedBranchID != nil &&
        priceDecimal != nil
    }

    private var priceDecimal: Decimal? {
        Decimal(string: priceText.replacingOccurrences(of: ",", with: "."))
    }

    private func addNewStore() {
        let chain = newStoreName.trimmingCharacters(in: .whitespaces)
        guard !chain.isEmpty else { return }
        let branch = newBranchName.trimmingCharacters(in: .whitespaces)
        let newBranch = store.createStoreBranch(
            chainName: chain,
            branchName: branch.isEmpty ? chain : branch
        )
        selectedBranchID = newBranch.id
        newStoreName = ""
        newBranchName = ""
        showAddStore = false
    }

    private func save() {
        guard let price = priceDecimal,
              let branchID = selectedBranchID,
              let branch = store.branches.first(where: { $0.id == branchID }) else { return }

        let trimmedName = productName.trimmingCharacters(in: .whitespaces)
        let product: Product
        if let idx = store.products.firstIndex(where: { $0.name.lowercased() == trimmedName.lowercased() }) {
            if let barcode = prefilledBarcode, store.products[idx].barcode == nil {
                store.products[idx].barcode = barcode
            }
            product = store.products[idx]
        } else {
            let new = Product(name: trimmedName, barcode: prefilledBarcode)
            store.products.append(new)
            product = new
        }

        let quantity = showsQuantity ? Double(quantityText.replacingOccurrences(of: ",", with: ".")) : nil
        let unit: MeasurementUnit? = (showsQuantity && quantity != nil) ? selectedUnit : nil

        let obs = PriceObservation(
            productID: product.id,
            productName: trimmedName,
            storeBranchID: branchID,
            storeBranchName: branch.displayName,
            price: price,
            quantity: quantity,
            unit: unit,
            isPromotion: isPromotion,
            priceKind: priceKind == .regular ? nil : priceKind,
            promotionEndDate: isPromotion ? promotionEndDate : nil,
            observedDate: observedDate,
            source: .manual
        )
        store.priceObservations.append(obs)
        store.queueCommunityContributionIfNeeded(for: obs)
        store.persistNow()
    }
}

// MARK: - Add Product

struct AddProductSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category = ""
    @State private var selectedUnit: MeasurementUnit = .grams
    @State private var hasDefaultUnit = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Product") {
                    TextField("Name (e.g. Minced beef)", text: $name)
                    TextField("Category (e.g. Meat, Dairy)", text: $category)
                }
                Section("Default unit (optional)") {
                    Toggle("Set default unit", isOn: $hasDefaultUnit.animation())
                    if hasDefaultUnit {
                        Picker("Unit", selection: $selectedUnit) {
                            ForEach(MeasurementUnit.allCases) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        let cat = category.trimmingCharacters(in: .whitespaces)
                        let product = Product(
                            name: trimmed,
                            category: cat.isEmpty ? nil : cat,
                            defaultUnit: hasDefaultUnit ? selectedUnit : nil
                        )
                        store.products.append(product)
                        store.persistNow()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Add Recipe

struct AddRecipeSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var servings = 4
    @State private var scope: DataScope = .personal
    @State private var ingredients: [DraftIngredient] = [DraftIngredient()]

    struct DraftIngredient: Identifiable {
        let id = UUID()
        var name = ""
        var quantity = ""
        var unit: MeasurementUnit = .grams
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipe") {
                    TextField("Title", text: $title)
                    TextField("Description (optional)", text: $description)
                    Stepper("Servings: \(servings)", value: $servings, in: 1...20)
                }

                if store.household != nil {
                    Section("Scope") {
                        Picker("Scope", selection: $scope) {
                            Text("Personal").tag(DataScope.personal)
                            Text("Household").tag(DataScope.household)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section("Ingredients") {
                    ForEach($ingredients) { $ingredient in
                        HStack(spacing: 8) {
                            TextField("Ingredient", text: $ingredient.name)
                            TextField("Qty", text: $ingredient.quantity)
                                .frame(width: 50)
                                .keyboardType(.decimalPad)
                            Picker("", selection: $ingredient.unit) {
                                ForEach(MeasurementUnit.allCases) { unit in
                                    Text(unit.rawValue).tag(unit)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 55)
                        }
                    }
                    .onDelete { ingredients.remove(atOffsets: $0) }
                    Button("Add ingredient") {
                        ingredients.append(DraftIngredient())
                    }
                }
            }
            .navigationTitle("New Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveRecipe()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func saveRecipe() {
        var recipe = Recipe(title: title.trimmingCharacters(in: .whitespaces), servings: servings)
        if !description.isEmpty { recipe.description = description.trimmingCharacters(in: .whitespaces) }
        recipe.scope = scope
        recipe.ingredients = ingredients.compactMap { draft in
            let name = draft.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, let qty = Double(draft.quantity.replacingOccurrences(of: ",", with: ".")) else { return nil }
            return RecipeIngredient(productName: name, quantity: qty, unit: draft.unit)
        }
        store.recipes.append(recipe)
        store.persistNow()
    }
}
