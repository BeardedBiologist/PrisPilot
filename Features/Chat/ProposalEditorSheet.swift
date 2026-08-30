import SwiftUI

// MARK: - Proposal Editor Sheet

struct ProposalEditorSheet: View {
    let action: ProposedAction
    let onSave: (ProposedActionPayload, String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            editorContent
                .navigationTitle("Edit")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var editorContent: some View {
        switch action.payload {
        case .addShoppingListItem(let list, let product, let qty, let notes):
            AddItemEditor(listName: list, productName: product, quantity: qty, notes: notes ?? "", onSave: save)
        case .createPriceObservation(let product, let store, let price, let qty, let unit, let isPromo, let date):
            CreatePriceEditor(productName: product, storeName: store, price: price, quantity: qty, unit: unit, isPromotion: isPromo, date: date, onSave: save)
        case .updatePriceObservation(let product, let store, let price, let qty, let unit):
            UpdatePriceEditor(productName: product, storeName: store ?? "", price: price, quantity: qty, unit: unit, onSave: save)
        case .createRecipe(let title, let description, let servings, let ingredients, let steps, let tags, let author, let prepTime, let cookTime):
            CreateRecipeEditor(title: title, description: description, servings: servings, ingredients: ingredients, steps: steps, tags: tags, author: author, prepTimeMinutes: prepTime, cookTimeMinutes: cookTime, onSave: save)
        case .updateRecipe(let existing, let newTitle, let desc, let servings):
            UpdateRecipeEditor(existingTitle: existing, newTitle: newTitle ?? existing, description: desc ?? "", servings: servings ?? 2, onSave: save)
        case .createShoppingList(let name):
            CreateListEditor(name: name, onSave: save)
        case .updateShoppingList(let existing, let newName, let date):
            UpdateListEditor(existingName: existing, newName: newName ?? existing, plannedDate: date, onSave: save)
        case .createMemory(let summary, let category, let strength, let sensitivity):
            CreateMemoryEditor(summary: summary, category: category, strength: strength, sensitivityLevel: sensitivity, onSave: save)
        case .setMealPlanSlot(let date, let mealType, let recipeTitle, let freeform, let isEatingOut, let isLeftover):
            SetMealSlotEditor(date: date, mealType: mealType, recipeTitle: recipeTitle ?? "", freeformText: freeform ?? "", isEatingOut: isEatingOut, isLeftover: isLeftover, onSave: save)
        case .createMatkasseBox(let provider, let week, let meals, let servings, let price, let notes):
            CreateMatkasseEditor(provider: provider, deliveryWeek: week ?? Date(), numberOfMeals: meals ?? 4, servingsPerMeal: servings ?? 2, price: price, notes: notes ?? "", onSave: save)
        case .addMatkasseMeal(let boxProvider, let mealTitle):
            AddMatkasseMealEditor(boxProvider: boxProvider, mealTitle: mealTitle, onSave: save)
        case .createStore(let chain, let branch, let address, let enabled):
            CreateStoreEditor(chainName: chain, branchName: branch, address: address ?? "", isEnabled: enabled, onSave: save)
        case .updateStore(let existing, let chain, let branch, let address, let enabled):
            UpdateStoreEditor(existingStoreName: existing, chainName: chain ?? "", branchName: branch ?? "", address: address ?? "", isEnabled: enabled, onSave: save)
        case .setStoreEnabled(let storeName, let enabled):
            StoreEnabledEditor(storeName: storeName, isEnabled: enabled, onSave: save)
        case .updateMemory(let existing, let newSummary, let category, let strength, let sensitivity):
            UpdateMemoryEditor(
                existingSummary: existing,
                newSummary: newSummary ?? existing,
                category: category ?? .preference,
                strength: strength ?? .preference,
                sensitivityLevel: sensitivity ?? .standard,
                onSave: save
            )
        default:
            notSupportedView
        }
    }

    private func save(_ payload: ProposedActionPayload, _ summary: String) {
        onSave(payload, summary)
        dismiss()
    }

    private var notSupportedView: some View {
        ContentUnavailableView(
            "Not Editable",
            systemImage: "pencil.slash",
            description: Text("This action type cannot be edited directly.")
        )
    }
}

// MARK: - Add Shopping List Item

private struct AddItemEditor: View {
    @State private var listName: String
    @State private var productName: String
    @State private var quantity: String
    @State private var notes: String
    let onSave: (ProposedActionPayload, String) -> Void

    init(listName: String, productName: String, quantity: String, notes: String, onSave: @escaping (ProposedActionPayload, String) -> Void) {
        _listName = State(initialValue: listName)
        _productName = State(initialValue: productName)
        _quantity = State(initialValue: quantity)
        _notes = State(initialValue: notes)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Product") {
                TextField("Product name", text: $productName)
                TextField("Quantity (e.g. 2 stk)", text: $quantity)
                TextField("Notes (optional)", text: $notes)
            }
            Section("List") {
                TextField("List name", text: $listName)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(
                        .addShoppingListItem(listName: listName, productName: productName, quantity: quantity, notes: notes.isEmpty ? nil : notes),
                        "Add \(productName) (\(quantity)) to \(listName)"
                    )
                }
                .disabled(productName.trimmed.isEmpty || listName.trimmed.isEmpty)
            }
        }
    }
}

// MARK: - Create Price Observation

private struct CreatePriceEditor: View {
    @State private var productName: String
    @State private var storeName: String
    @State private var priceText: String
    @State private var quantityText: String
    @State private var unit: MeasurementUnit?
    @State private var isPromotion: Bool
    @State private var date: Date
    let onSave: (ProposedActionPayload, String) -> Void

    init(productName: String, storeName: String, price: Decimal, quantity: Double?, unit: MeasurementUnit?, isPromotion: Bool, date: Date, onSave: @escaping (ProposedActionPayload, String) -> Void) {
        _productName = State(initialValue: productName)
        _storeName = State(initialValue: storeName)
        _priceText = State(initialValue: "\(price)")
        _quantityText = State(initialValue: quantity.map { "\($0)" } ?? "")
        _unit = State(initialValue: unit)
        _isPromotion = State(initialValue: isPromotion)
        _date = State(initialValue: date)
        self.onSave = onSave
    }

    private var parsedPrice: Decimal? { Decimal(string: priceText) }
    private var canSave: Bool {
        !productName.trimmed.isEmpty && !storeName.trimmed.isEmpty && parsedPrice != nil
    }

    var body: some View {
        Form {
            Section("Price") {
                TextField("Product name", text: $productName)
                TextField("Store (e.g. Kiwi sentrum)", text: $storeName)
                HStack {
                    Text("kr").foregroundStyle(.secondary)
                    TextField("Price", text: $priceText).keyboardType(.decimalPad)
                }
            }
            Section("Package") {
                TextField("Quantity (optional)", text: $quantityText).keyboardType(.decimalPad)
                Picker("Unit", selection: $unit) {
                    Text("None").tag(Optional<MeasurementUnit>.none)
                    ForEach(MeasurementUnit.allCases) { u in
                        Text(u.rawValue).tag(Optional(u))
                    }
                }
                Toggle("Promotion price", isOn: $isPromotion)
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let price = parsedPrice else { return }
                    let qty = Double(quantityText)
                    let qtyStr = qty.map { " \($0)\(unit?.rawValue ?? "")" } ?? ""
                    onSave(
                        .createPriceObservation(productName: productName, storeBranchName: storeName, price: price, quantity: qty, unit: unit, isPromotion: isPromotion, date: date),
                        "Log kr \(price)\(qtyStr) for \(productName) at \(storeName)"
                    )
                }
                .disabled(!canSave)
            }
        }
    }
}

// MARK: - Update Price Observation

private struct UpdatePriceEditor: View {
    @State private var productName: String
    @State private var storeName: String
    @State private var priceText: String
    @State private var quantityText: String
    @State private var unit: MeasurementUnit?
    let onSave: (ProposedActionPayload, String) -> Void

    init(productName: String, storeName: String, price: Decimal?, quantity: Double?, unit: MeasurementUnit?, onSave: @escaping (ProposedActionPayload, String) -> Void) {
        _productName = State(initialValue: productName)
        _storeName = State(initialValue: storeName)
        _priceText = State(initialValue: price.map { "\($0)" } ?? "")
        _quantityText = State(initialValue: quantity.map { "\($0)" } ?? "")
        _unit = State(initialValue: unit)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Price") {
                TextField("Product name", text: $productName)
                TextField("Store (optional)", text: $storeName)
                HStack {
                    Text("kr").foregroundStyle(.secondary)
                    TextField("New price", text: $priceText).keyboardType(.decimalPad)
                }
            }
            Section("Package") {
                TextField("New quantity (optional)", text: $quantityText).keyboardType(.decimalPad)
                Picker("Unit", selection: $unit) {
                    Text("None").tag(Optional<MeasurementUnit>.none)
                    ForEach(MeasurementUnit.allCases) { u in
                        Text(u.rawValue).tag(Optional(u))
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let price = Decimal(string: priceText)
                    let qty = Double(quantityText)
                    let priceStr = price.map { "kr \($0)" } ?? ""
                    onSave(
                        .updatePriceObservation(productName: productName, storeBranchName: storeName.isEmpty ? nil : storeName, newPrice: price, newQuantity: qty, newUnit: unit),
                        "Update price\(priceStr.isEmpty ? "" : " to \(priceStr)") for \(productName)"
                    )
                }
                .disabled(productName.trimmed.isEmpty)
            }
        }
    }
}

// MARK: - Create Recipe

private struct CreateRecipeEditor: View {
    @State private var title: String
    @State private var servings: Int
    private let description: String?
    private let ingredients: [RecipeIngredient]
    private let steps: [String]
    private let tags: [String]
    private let author: String?
    private let prepTimeMinutes: Int?
    private let cookTimeMinutes: Int?
    let onSave: (ProposedActionPayload, String) -> Void

    init(title: String, description: String?, servings: Int, ingredients: [RecipeIngredient], steps: [String], tags: [String], author: String?, prepTimeMinutes: Int?, cookTimeMinutes: Int?, onSave: @escaping (ProposedActionPayload, String) -> Void) {
        _title = State(initialValue: title)
        _servings = State(initialValue: max(1, servings))
        self.description = description
        self.ingredients = ingredients
        self.steps = steps
        self.tags = tags
        self.author = author
        self.prepTimeMinutes = prepTimeMinutes
        self.cookTimeMinutes = cookTimeMinutes
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Recipe") {
                TextField("Title", text: $title)
                Stepper("Servings: \(servings)", value: $servings, in: 1...20)
                if !ingredients.isEmpty {
                    LabeledContent("Ingredients", value: "\(ingredients.count)")
                }
                if !steps.isEmpty {
                    LabeledContent("Steps", value: "\(steps.count)")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(.createRecipe(title: title, description: description, servings: servings, ingredients: ingredients, steps: steps, tags: tags, author: author, prepTimeMinutes: prepTimeMinutes, cookTimeMinutes: cookTimeMinutes), "Create recipe \"\(title)\" (\(servings) servings)")
                }
                .disabled(title.trimmed.isEmpty)
            }
        }
    }
}

// MARK: - Update Recipe

private struct UpdateRecipeEditor: View {
    let existingTitle: String
    @State private var newTitle: String
    @State private var description: String
    @State private var servings: Int
    let onSave: (ProposedActionPayload, String) -> Void

    init(existingTitle: String, newTitle: String, description: String, servings: Int, onSave: @escaping (ProposedActionPayload, String) -> Void) {
        self.existingTitle = existingTitle
        _newTitle = State(initialValue: newTitle)
        _description = State(initialValue: description)
        _servings = State(initialValue: max(1, servings))
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Recipe") {
                TextField("Title", text: $newTitle)
                TextField("Description (optional)", text: $description, axis: .vertical)
                    .lineLimit(2...5)
                Stepper("Servings: \(servings)", value: $servings, in: 1...20)
            }
            Section {
                LabeledContent("Updating", value: existingTitle).foregroundStyle(.secondary)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let t = newTitle.trimmed.isEmpty ? existingTitle : newTitle
                    onSave(
                        .updateRecipe(existingTitle: existingTitle, newTitle: newTitle.trimmed.isEmpty ? nil : newTitle, description: description.isEmpty ? nil : description, servings: servings),
                        "Update recipe \"\(t)\""
                    )
                }
            }
        }
    }
}

// MARK: - Create Shopping List

private struct CreateListEditor: View {
    @State private var name: String
    let onSave: (ProposedActionPayload, String) -> Void

    init(name: String, onSave: @escaping (ProposedActionPayload, String) -> Void) {
        _name = State(initialValue: name)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("List") {
                TextField("List name", text: $name)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(.createShoppingList(name: name), "Create shopping list \"\(name)\"")
                }
                .disabled(name.trimmed.isEmpty)
            }
        }
    }
}

// MARK: - Update Shopping List

private struct UpdateListEditor: View {
    let existingName: String
    @State private var newName: String
    @State private var plannedDate: Date
    @State private var hasDate: Bool
    let onSave: (ProposedActionPayload, String) -> Void

    init(existingName: String, newName: String, plannedDate: Date?, onSave: @escaping (ProposedActionPayload, String) -> Void) {
        self.existingName = existingName
        _newName = State(initialValue: newName)
        _plannedDate = State(initialValue: plannedDate ?? Date())
        _hasDate = State(initialValue: plannedDate != nil)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("List") {
                TextField("New name", text: $newName)
                Toggle("Set planned date", isOn: $hasDate)
                if hasDate {
                    DatePicker("Planned date", selection: $plannedDate, displayedComponents: .date)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let finalName = newName.trimmed.isEmpty ? nil : newName
                    let n = finalName ?? existingName
                    onSave(
                        .updateShoppingList(existingListName: existingName, newName: finalName, plannedDate: hasDate ? plannedDate : nil),
                        "Update list \"\(n)\""
                    )
                }
            }
        }
    }
}

// MARK: - Create Memory

private struct CreateMemoryEditor: View {
    @State private var summary: String
    @State private var category: MemoryCategory
    @State private var strength: ConstraintStrength
    @State private var sensitivityLevel: SensitivityLevel
    let onSave: (ProposedActionPayload, String) -> Void

    init(summary: String, category: MemoryCategory, strength: ConstraintStrength, sensitivityLevel: SensitivityLevel, onSave: @escaping (ProposedActionPayload, String) -> Void) {
        _summary = State(initialValue: summary)
        _category = State(initialValue: category)
        _strength = State(initialValue: strength)
        _sensitivityLevel = State(initialValue: sensitivityLevel)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Memory") {
                TextField("Summary", text: $summary, axis: .vertical)
                    .lineLimit(3...6)
            }
            Section("Classification") {
                Picker("Category", selection: $category) {
                    ForEach(MemoryCategory.allCases, id: \.self) { cat in
                        Label(cat.rawValue, systemImage: cat.systemImage).tag(cat)
                    }
                }
                Picker("Strength", selection: $strength) {
                    ForEach(ConstraintStrength.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                Picker("Sensitivity", selection: $sensitivityLevel) {
                    ForEach(SensitivityLevel.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(.createMemory(summary: summary, category: category, strength: strength, sensitivityLevel: sensitivityLevel), "Remember: \(summary)")
                }
                .disabled(summary.trimmed.isEmpty)
            }
        }
    }
}

// MARK: - Set Meal Slot

private struct SetMealSlotEditor: View {
    @State private var date: Date
    @State private var mealType: String
    @State private var recipeTitle: String
    @State private var freeformText: String
    @State private var isEatingOut: Bool
    @State private var isLeftover: Bool
    let onSave: (ProposedActionPayload, String) -> Void

    private let mealTypeOptions = ["breakfast", "lunch", "dinner", "snack"]

    init(date: Date, mealType: String, recipeTitle: String, freeformText: String, isEatingOut: Bool, isLeftover: Bool, onSave: @escaping (ProposedActionPayload, String) -> Void) {
        _date = State(initialValue: date)
        _mealType = State(initialValue: mealType)
        _recipeTitle = State(initialValue: recipeTitle)
        _freeformText = State(initialValue: freeformText)
        _isEatingOut = State(initialValue: isEatingOut)
        _isLeftover = State(initialValue: isLeftover)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("When") {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Meal", selection: $mealType) {
                    ForEach(mealTypeOptions, id: \.self) { type in
                        Text(type.capitalized).tag(type)
                    }
                }
            }
            Section("What") {
                if isEatingOut {
                    Text("Eating out").foregroundStyle(.secondary)
                } else {
                    TextField("Recipe name", text: $recipeTitle)
                    TextField("Or freeform note", text: $freeformText)
                }
                Toggle("Eating out", isOn: $isEatingOut)
                Toggle("Leftover / cook-once", isOn: $isLeftover)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let rt = recipeTitle.trimmed.isEmpty ? nil : recipeTitle
                    let ft = freeformText.trimmed.isEmpty ? nil : freeformText
                    let mealDesc = isEatingOut ? "Eating out" : (rt ?? ft ?? mealType.capitalized)
                    let dateStr = date.formatted(date: .abbreviated, time: .omitted)
                    onSave(
                        .setMealPlanSlot(date: date, mealType: mealType, recipeTitle: rt, freeformText: ft, isEatingOut: isEatingOut, isLeftover: isLeftover),
                        "Plan \(mealType) on \(dateStr): \(mealDesc)"
                    )
                }
            }
        }
    }
}

// MARK: - Create Matkasse Box

private struct CreateMatkasseEditor: View {
    @State private var provider: String
    @State private var deliveryWeek: Date
    @State private var numberOfMeals: Int
    @State private var servingsPerMeal: Int
    @State private var priceText: String
    @State private var notes: String
    let onSave: (ProposedActionPayload, String) -> Void

    init(provider: String, deliveryWeek: Date, numberOfMeals: Int, servingsPerMeal: Int, price: Decimal?, notes: String, onSave: @escaping (ProposedActionPayload, String) -> Void) {
        _provider = State(initialValue: provider)
        _deliveryWeek = State(initialValue: deliveryWeek)
        _numberOfMeals = State(initialValue: max(1, numberOfMeals))
        _servingsPerMeal = State(initialValue: max(1, servingsPerMeal))
        _priceText = State(initialValue: price.map { "\($0)" } ?? "")
        _notes = State(initialValue: notes)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Provider") {
                TextField("Provider (e.g. Adams Matkasse)", text: $provider)
                DatePicker("Delivery week", selection: $deliveryWeek, displayedComponents: .date)
            }
            Section("Box contents") {
                Stepper("Meals: \(numberOfMeals)", value: $numberOfMeals, in: 1...10)
                Stepper("Servings per meal: \(servingsPerMeal)", value: $servingsPerMeal, in: 1...8)
                HStack {
                    Text("kr").foregroundStyle(.secondary)
                    TextField("Price (optional)", text: $priceText).keyboardType(.decimalPad)
                }
                TextField("Notes (optional)", text: $notes)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let price = Decimal(string: priceText)
                    onSave(
                        .createMatkasseBox(provider: provider, deliveryWeek: deliveryWeek, numberOfMeals: numberOfMeals, servingsPerMeal: servingsPerMeal, price: price, notes: notes.isEmpty ? nil : notes),
                        "Add matkasse box from \(provider) (\(numberOfMeals) meals)"
                    )
                }
                .disabled(provider.trimmed.isEmpty)
            }
        }
    }
}

// MARK: - Add Matkasse Meal

private struct AddMatkasseMealEditor: View {
    @State private var boxProvider: String
    @State private var mealTitle: String
    let onSave: (ProposedActionPayload, String) -> Void

    init(boxProvider: String, mealTitle: String, onSave: @escaping (ProposedActionPayload, String) -> Void) {
        _boxProvider = State(initialValue: boxProvider)
        _mealTitle = State(initialValue: mealTitle)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Meal") {
                TextField("Meal title", text: $mealTitle)
                TextField("Box provider", text: $boxProvider)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(.addMatkasseMeal(boxProvider: boxProvider, mealTitle: mealTitle), "Add \"\(mealTitle)\" to \(boxProvider) box")
                }
                .disabled(mealTitle.trimmed.isEmpty || boxProvider.trimmed.isEmpty)
            }
        }
    }
}

// MARK: - Create Store

private struct CreateStoreEditor: View {
    @State private var chainName: String
    @State private var branchName: String
    @State private var address: String
    @State private var isEnabled: Bool
    let onSave: (ProposedActionPayload, String) -> Void

    init(chainName: String, branchName: String, address: String, isEnabled: Bool, onSave: @escaping (ProposedActionPayload, String) -> Void) {
        _chainName = State(initialValue: chainName)
        _branchName = State(initialValue: branchName)
        _address = State(initialValue: address)
        _isEnabled = State(initialValue: isEnabled)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Store") {
                TextField("Chain (e.g. Kiwi)", text: $chainName)
                TextField("Branch (e.g. Sentrum)", text: $branchName)
                TextField("Address (optional)", text: $address)
                Toggle("Enabled for price comparison", isOn: $isEnabled)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(
                        .createStore(chainName: chainName, branchName: branchName, address: address.isEmpty ? nil : address, isEnabled: isEnabled),
                        "Add store \(chainName) \(branchName)"
                    )
                }
                .disabled(chainName.trimmed.isEmpty || branchName.trimmed.isEmpty)
            }
        }
    }
}

private struct UpdateStoreEditor: View {
    @State private var existingStoreName: String
    @State private var chainName: String
    @State private var branchName: String
    @State private var address: String
    @State private var isEnabled: Bool?
    let onSave: (ProposedActionPayload, String) -> Void

    init(existingStoreName: String, chainName: String, branchName: String, address: String, isEnabled: Bool?, onSave: @escaping (ProposedActionPayload, String) -> Void) {
        _existingStoreName = State(initialValue: existingStoreName)
        _chainName = State(initialValue: chainName)
        _branchName = State(initialValue: branchName)
        _address = State(initialValue: address)
        _isEnabled = State(initialValue: isEnabled)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Store") {
                TextField("Existing store", text: $existingStoreName)
                TextField("New chain name", text: $chainName)
                TextField("New branch name", text: $branchName)
                TextField("Address", text: $address)
                Picker("Enabled", selection: enabledBinding) {
                    Text("No change").tag(Optional<Bool>.none)
                    Text("Enabled").tag(Optional(true))
                    Text("Disabled").tag(Optional(false))
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(
                        .updateStore(
                            existingStoreName: existingStoreName,
                            chainName: chainName.trimmed.nilIfEmpty,
                            branchName: branchName.trimmed.nilIfEmpty,
                            address: address.trimmed.nilIfEmpty,
                            isEnabled: isEnabled
                        ),
                        "Update store: \(existingStoreName)"
                    )
                }
                .disabled(existingStoreName.trimmed.isEmpty)
            }
        }
    }

    private var enabledBinding: Binding<Bool?> {
        Binding {
            isEnabled
        } set: { value in
            isEnabled = value
        }
    }
}

private struct StoreEnabledEditor: View {
    @State private var storeName: String
    @State private var isEnabled: Bool
    let onSave: (ProposedActionPayload, String) -> Void

    init(storeName: String, isEnabled: Bool, onSave: @escaping (ProposedActionPayload, String) -> Void) {
        _storeName = State(initialValue: storeName)
        _isEnabled = State(initialValue: isEnabled)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Store") {
                TextField("Store name", text: $storeName)
                Toggle("Enabled", isOn: $isEnabled)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(
                        .setStoreEnabled(storeName: storeName, isEnabled: isEnabled),
                        "\(isEnabled ? "Enable" : "Disable") store: \(storeName)"
                    )
                }
                .disabled(storeName.trimmed.isEmpty)
            }
        }
    }
}

private struct UpdateMemoryEditor: View {
    @State private var existingSummary: String
    @State private var newSummary: String
    @State private var category: MemoryCategory
    @State private var strength: ConstraintStrength
    @State private var sensitivityLevel: SensitivityLevel
    let onSave: (ProposedActionPayload, String) -> Void

    init(existingSummary: String, newSummary: String, category: MemoryCategory, strength: ConstraintStrength, sensitivityLevel: SensitivityLevel, onSave: @escaping (ProposedActionPayload, String) -> Void) {
        _existingSummary = State(initialValue: existingSummary)
        _newSummary = State(initialValue: newSummary)
        _category = State(initialValue: category)
        _strength = State(initialValue: strength)
        _sensitivityLevel = State(initialValue: sensitivityLevel)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Memory") {
                TextField("Existing memory", text: $existingSummary, axis: .vertical)
                    .lineLimit(2...5)
                TextField("New memory", text: $newSummary, axis: .vertical)
                    .lineLimit(2...5)
            }
            Section("Classification") {
                Picker("Category", selection: $category) {
                    ForEach(MemoryCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Strength", selection: $strength) {
                    ForEach(ConstraintStrength.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Sensitivity", selection: $sensitivityLevel) {
                    ForEach(SensitivityLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(
                        .updateMemory(
                            existingSummary: existingSummary,
                            newSummary: newSummary.trimmed.nilIfEmpty,
                            category: category,
                            strength: strength,
                            sensitivityLevel: sensitivityLevel
                        ),
                        "Update memory: \(existingSummary)"
                    )
                }
                .disabled(existingSummary.trimmed.isEmpty || newSummary.trimmed.isEmpty)
            }
        }
    }
}

// MARK: - String Helper

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
