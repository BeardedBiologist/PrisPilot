import SwiftUI

/// Matkasse boxes list — opened from the Meals tab's toolbar, same pattern
/// as `RecipesListView`. Deliberately unbranded per the product plan:
/// `provider` is free text the user fills in themselves, never a fixed
/// picker of named services.
struct MatkasseListView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showAddBox = false

    var body: some View {
        NavigationStack {
            List {
                if store.matkasseBoxes.isEmpty {
                    ContentUnavailableView(
                        "No Matkasse Boxes Yet",
                        systemImage: "shippingbox",
                        description: Text("Add a box to place its meals on the planner without them generating grocery-list items.")
                    )
                } else {
                    ForEach(store.matkasseBoxes.sorted(by: { $0.deliveryWeekStartDate < $1.deliveryWeekStartDate })) { box in
                        NavigationLink(destination: MatkasseBoxDetailView(boxID: box.id).environment(store)) {
                            MatkasseBoxRow(box: box)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.deleteMatkasseBox(box.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Matkasse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddBox = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add matkasse box")
                }
            }
            .sheet(isPresented: $showAddBox) {
                AddMatkasseBoxSheet().environment(store)
            }
        }
    }
}

private struct MatkasseBoxRow: View {
    let box: MatkasseBox

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(box.provider)
                    .font(.headline)
                Text("Delivery week of \(box.deliveryWeekStartDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(box.includedMeals.count)/\(box.numberOfMeals) meals added · \(box.servingsPerMeal) servings each")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let price = box.price {
                Text("kr \(NSDecimalNumber(decimal: price).stringValue)")
                    .font(.subheadline.weight(.medium))
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Box Detail

struct MatkasseBoxDetailView: View {
    @Environment(AppStore.self) private var store
    let boxID: UUID

    @State private var showAddMeal = false

    private var box: MatkasseBox? { store.matkasseBoxes.first { $0.id == boxID } }

    var body: some View {
        List {
            if let box {
                Section("Box") {
                    LabeledContent("Provider", value: box.provider)
                    LabeledContent("Delivery week", value: box.deliveryWeekStartDate.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("Meals", value: "\(box.numberOfMeals)")
                    LabeledContent("Servings per meal", value: "\(box.servingsPerMeal)")
                    if let price = box.price {
                        LabeledContent("Price", value: "kr \(NSDecimalNumber(decimal: price).stringValue)")
                    }
                    if let notes = box.notes, !notes.isEmpty {
                        LabeledContent("Notes", value: notes)
                    }
                }

                Section {
                    if box.includedMeals.isEmpty {
                        Text("No meals added yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(box.includedMeals) { meal in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meal.title)
                                    .font(.subheadline)
                                if !meal.ingredients.isEmpty {
                                    Text("\(meal.ingredients.count) ingredient\(meal.ingredients.count == 1 ? "" : "s") saved")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                store.removeMatkasseMeal(box.includedMeals[index].id, from: box.id)
                            }
                        }
                    }
                } header: {
                    Text("Meals")
                } footer: {
                    Text("These can be placed on the planner from a meal slot's editor. They don't generate shopping-list items — the box is already delivering them.")
                }
            }
        }
        .navigationTitle(box?.provider ?? "Matkasse Box")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAddMeal = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add meal")
            }
        }
        .sheet(isPresented: $showAddMeal) {
            AddMatkasseMealSheet(boxID: boxID).environment(store)
        }
    }
}

// MARK: - Add Matkasse Box

struct AddMatkasseBoxSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var provider = ""
    @State private var deliveryWeekStartDate = Date()
    @State private var numberOfMeals = 4
    @State private var servingsPerMeal = 2
    @State private var priceText = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Box") {
                    TextField("Provider (e.g. Adams Matkasse)", text: $provider)
                        .autocorrectionDisabled()
                    DatePicker("Delivery week", selection: $deliveryWeekStartDate, displayedComponents: .date)
                    Stepper("Meals: \(numberOfMeals)", value: $numberOfMeals, in: 1...14)
                    Stepper("Servings per meal: \(servingsPerMeal)", value: $servingsPerMeal, in: 1...10)
                }

                Section("Price") {
                    HStack {
                        Text("kr").foregroundStyle(.secondary)
                        TextField("Optional", text: $priceText)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("New Matkasse Box")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(provider.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        let price = Decimal(string: priceText.replacingOccurrences(of: ",", with: "."))
        store.createMatkasseBox(
            provider: provider.trimmingCharacters(in: .whitespaces),
            deliveryWeekStartDate: Calendar.mealPlanCalendar.dateInterval(of: .weekOfYear, for: deliveryWeekStartDate)?.start ?? deliveryWeekStartDate,
            numberOfMeals: numberOfMeals,
            servingsPerMeal: servingsPerMeal,
            price: price,
            notes: notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes
        )
        dismiss()
    }
}

// MARK: - Add Matkasse Meal

struct AddMatkasseMealSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let boxID: UUID

    @State private var title = ""
    @State private var ingredients: [DraftIngredient] = []

    struct DraftIngredient: Identifiable {
        let id = UUID()
        var name = ""
        var quantity = ""
        var unit: MeasurementUnit = .grams
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    TextField("Title", text: $title)
                }

                Section {
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
                } header: {
                    Text("Ingredients (optional)")
                } footer: {
                    Text("Saved for cost tracking only — matkasse meals don't feed shopping-list generation.")
                }
            }
            .navigationTitle("New Matkasse Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        let resolvedIngredients: [RecipeIngredient] = ingredients.compactMap { draft in
            let name = draft.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, let qty = Double(draft.quantity.replacingOccurrences(of: ",", with: ".")) else { return nil }
            return RecipeIngredient(productName: name, quantity: qty, unit: draft.unit)
        }
        store.addMatkasseMeal(to: boxID, title: title.trimmingCharacters(in: .whitespaces), ingredients: resolvedIngredients)
        dismiss()
    }
}
