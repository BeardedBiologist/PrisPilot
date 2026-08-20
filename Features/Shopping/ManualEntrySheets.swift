import SwiftUI

// MARK: - Add Shopping List

struct AddShoppingListSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("List name") {
                    TextField("e.g. Weekly Shop, Taco Night", text: $name)
                        .autocorrectionDisabled()
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
                        store.shoppingLists.append(ShoppingList(name: trimmed))
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
    @State private var quantity = "1"
    @State private var notes = ""

    private var listName: String {
        store.shoppingLists.first { $0.id == listID }?.name ?? "List"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Product name", text: $productName)
                    TextField("Quantity (e.g. 2, 400 g, 1 pack)", text: $quantity)
                }
                Section("Notes (optional)") {
                    TextField("Add a note", text: $notes)
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
            requestedQuantity: quantity.trimmingCharacters(in: .whitespaces).isEmpty ? "1" : quantity
        )
        if !notes.isEmpty { item.notes = notes.trimmingCharacters(in: .whitespaces) }
        store.shoppingLists[idx].items.append(item)
        store.persistNow()
    }
}

// MARK: - Add Price Observation

struct AddPriceObservationSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var productName = ""
    @State private var selectedBranchID: UUID? = nil
    @State private var priceText = ""
    @State private var quantityText = ""
    @State private var selectedUnit: MeasurementUnit = .grams
    @State private var isPromotion = false
    @State private var observedDate = Date()
    @State private var showsQuantity = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Product") {
                    TextField("Product name", text: $productName)
                        .autocorrectionDisabled()
                }

                Section("Store") {
                    if store.enabledBranches.isEmpty {
                        Text("No branches enabled — set up stores in Settings or Onboarding")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        Picker("Branch", selection: $selectedBranchID) {
                            Text("Select branch").tag(Optional<UUID>.none)
                            ForEach(store.enabledBranches) { branch in
                                Text(branch.displayName).tag(Optional(branch.id))
                            }
                        }
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

    private func save() {
        guard let price = priceDecimal,
              let branchID = selectedBranchID,
              let branch = store.branches.first(where: { $0.id == branchID }) else { return }

        let trimmedName = productName.trimmingCharacters(in: .whitespaces)
        let product: Product
        if let existing = store.products.first(where: { $0.name.lowercased() == trimmedName.lowercased() }) {
            product = existing
        } else {
            let new = Product(name: trimmedName)
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
            observedDate: observedDate,
            source: .manual
        )
        store.priceObservations.append(obs)
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
        recipe.ingredients = ingredients.compactMap { draft in
            let name = draft.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, let qty = Double(draft.quantity.replacingOccurrences(of: ",", with: ".")) else { return nil }
            return RecipeIngredient(productName: name, quantity: qty, unit: draft.unit)
        }
        store.recipes.append(recipe)
        store.persistNow()
    }
}
