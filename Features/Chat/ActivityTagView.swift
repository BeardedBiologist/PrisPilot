import SwiftUI

struct ActivityTagsView: View {
    let tags: [ActivityTag]

    var body: some View {
        if tags.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(Color(.systemGray3))
                Text("Actions rejected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(tags) { tag in
                    ActivityTagRow(tag: tag)
                }
            }
        }
    }
}

struct ActivityTagRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppStore.self) private var store
    let tag: ActivityTag
    @State private var showingDetail = false

    private var isMemory: Bool { tag.actionType.isMemoryAction }
    private var color: Color { isMemory ? .purple : .green }
    private var icon: String { isMemory ? "brain.head.profile" : "checkmark.circle.fill" }
    private var hasTappableRecord: Bool { !tag.affectedRecordIDs.isEmpty || tag.undoSnapshot != nil }

    var body: some View {
        Button {
            guard hasTappableRecord else { return }
            showingDetail = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(tag.summary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(colorScheme == .dark ? .white : .primary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                if hasTappableRecord {
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(color.opacity(0.5))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(color.opacity(0.2), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            ActivityTagDetailView(tag: tag)
                .environment(store)
        }
    }
}

// MARK: - Detail Sheet

struct ActivityTagDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.switchToShoppingTab) private var switchToShoppingTab
    @Environment(\.switchToPricesTab) private var switchToPricesTab
    @Environment(\.switchToRecipesTab) private var switchToRecipesTab
    @Environment(\.switchToSettingsTab) private var switchToSettingsTab
    let tag: ActivityTag
    @State private var showUndoConfirmation = false
    @State private var showUndoFailed = false

    private var firstID: UUID? { tag.affectedRecordIDs.first }

    var body: some View {
        NavigationStack {
            mainContent
        }
        .presentationDragIndicator(.visible)
        .alert("Undo this action?", isPresented: $showUndoConfirmation) {
            Button("Undo", role: .destructive) {
                if store.undoActivityTag(tag) {
                    dismiss()
                } else {
                    showUndoFailed = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(undoConfirmationMessage)
        }
        .alert("Could not undo", isPresented: $showUndoFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The record may already be deleted or may now be used by another price or store entry.")
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch tag.actionType {
        case .createShoppingList, .updateShoppingList,
             .addShoppingListItem, .updateShoppingListItem,
             .completeShoppingListItem, .removeShoppingListItem,
             .setShoppingListStatus, .optimizeShoppingList, .moveShoppingListItem,
             .substituteShoppingListItem, .addRecipeToShoppingList,
             .buildShoppingListFromMealPlan:
            if let listID = resolvedShoppingListID() {
                ShoppingListDetailView(listID: listID)
                    .toolbar { detailToolbar }
            } else {
                recordUnavailableView
            }

        case .createRecipe, .updateRecipe:
            if let recipe = firstID.flatMap({ id in store.recipes.first(where: { $0.id == id }) }) {
                RecipeDetailView(recipe: recipe)
                    .toolbar { detailToolbar }
            } else {
                recordUnavailableView
            }

        case .createPriceObservation, .updatePriceObservation,
             .confirmPriceObservation, .flagCommunityPrice:
            if let obs = firstID.flatMap({ id in store.priceObservations.first(where: { $0.id == id }) }) {
                PriceObservationDetailView(observation: obs)
                    .toolbar { detailToolbar }
            } else {
                recordUnavailableView
            }

        case .createMemory, .updateMemory, .deleteMemory:
            if let memory = firstID.flatMap({ id in store.memories.first(where: { $0.id == id }) }) {
                MemoryDetailView(memory: memory)
                    .toolbar { detailToolbar }
            } else {
                recordUnavailableView
            }

        case .createStore, .updateStore, .enableStore, .disableStore:
            if let branch = firstID.flatMap({ id in store.branches.first(where: { $0.id == id }) }) {
                StoreBranchDetailView(branch: branch)
                    .toolbar { detailToolbar }
            } else {
                recordUnavailableView
            }

        case .createProduct, .updateProduct, .deleteProduct, .mergeProducts,
             .addProductAlias, .removeProductAlias, .setProductBarcode:
            if let product = firstID.flatMap({ id in store.products.first(where: { $0.id == id }) }) {
                let history = store.priceObservations.filter { $0.productID == product.id }
                ProductDetailView(product: product, priceHistory: history)
                    .toolbar { detailToolbar }
            } else {
                recordUnavailableView
            }

        default:
            if tag.undoSnapshot != nil {
                undoOnlyView
            } else {
                recordUnavailableView
            }
        }
    }

    private var undoOnlyView: some View {
        ContentUnavailableView(
            tag.actionType.displayName,
            systemImage: tag.actionType.systemImage,
            description: Text("Action applied successfully. Use Undo in the toolbar to reverse it.")
        )
        .navigationTitle(tag.actionType.displayName)
        .toolbar { detailToolbar }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }

        if store.canUndoActivityTag(tag) {
            ToolbarItem(placement: .confirmationAction) {
                Button("Undo", role: .destructive) {
                    showUndoConfirmation = true
                }
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                navigateToActionDomain()
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .accessibilityLabel("Open related tab")
        }
    }

    private func navigateToActionDomain() {
        switch tag.actionType.domain {
        case .shopping:
            switchToShoppingTab()
        case .prices, .stores:
            switchToPricesTab()
        case .meals:
            switchToRecipesTab()
        case .memory, .settings:
            switchToSettingsTab()
        }
        dismiss()
    }

    private var recordUnavailableView: some View {
        ContentUnavailableView(
            "Record Unavailable",
            systemImage: tag.actionType.systemImage,
            description: Text("This record may have been deleted or is no longer available.")
        )
        .navigationTitle(tag.actionType.displayName)
        .toolbar { detailToolbar }
    }

    private var undoConfirmationMessage: String {
        guard let snapshot = tag.undoSnapshot else {
            return "This removes the record created by this AI action from local app data."
        }
        switch snapshot {
        case .deletedShoppingList, .deletedShoppingListItem, .deletedProduct, .deletedRecipe,
             .deletedPriceObservation, .deletedStoreBranch, .deletedMatkasseBox,
             .deletedMatkasseMeal, .deletedMemory:
            return "This restores the deleted record."
        case .createdShoppingList:
            return "This removes the shopping list created by this action."
        case .createdCommunityContribution:
            return "This removes the community flag record created by this action."
        case .createdInvitation:
            return "This removes the invitation created by this action."
        case .householdState:
            return "This restores the previous household state."
        case .productFields, .recipeFields, .shoppingListFields, .shoppingListStatusFields,
             .shoppingListItemFields, .shoppingListItemState, .priceObservationFields,
             .productMetadataFields, .storeBranchFields, .matkasseBoxFields,
             .communityContributionFlag:
            return "This restores the previous field values before the edit."
        case .addedMealPlanSlot:
            return "This removes the meal plan slot that was just added."
        case .overwrittenMealPlanSlot:
            return "This restores the meal plan slot that was overwritten."
        case .clearedMealPlanSlot:
            return "This restores the meal plan slot that was removed."
        }
    }

    private func resolvedShoppingListID() -> UUID? {
        guard let id = firstID else { return nil }
        if store.shoppingLists.contains(where: { $0.id == id }) { return id }
        return store.shoppingLists.first(where: { $0.items.contains(where: { $0.id == id }) })?.id
    }
}

// MARK: - Price Observation Detail

struct PriceObservationDetailView: View {
    let observation: PriceObservation

    var body: some View {
        List {
            Section {
                LabeledContent("Product", value: observation.productName)
                LabeledContent("Store", value: observation.storeBranchName)
                LabeledContent("Price", value: "\(observation.currency.symbol) \(NSDecimalNumber(decimal: observation.price).stringValue)")
                if let qty = observation.quantity {
                    let unit = observation.unit?.rawValue ?? ""
                    LabeledContent("Quantity", value: "\(qty.formatted()) \(unit)")
                }
                LabeledContent("Observed", value: observation.observedDate.formatted(date: .abbreviated, time: .omitted))
                if observation.isPromotion {
                    LabeledContent("Type", value: "Promotional price")
                }
                LabeledContent("Source", value: observation.source.rawValue)
            }
        }
        .navigationTitle("Price Record")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Memory Detail

struct MemoryDetailView: View {
    let memory: AIMemory

    var body: some View {
        List {
            Section {
                Text(memory.summary)
                    .font(.body)
                    .padding(.vertical, 2)
            }
            Section("Details") {
                LabeledContent("Category", value: memory.category.rawValue)
                LabeledContent("Strength", value: memory.strength.rawValue)
                if memory.sensitivityLevel != .standard {
                    LabeledContent("Sensitivity", value: memory.sensitivityLevel.rawValue)
                }
                LabeledContent("Scope", value: memory.scope.rawValue)
                LabeledContent("Saved", value: memory.createdAt.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .navigationTitle("AI Memory")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Store Branch Detail

struct StoreBranchDetailView: View {
    let branch: StoreBranch

    var body: some View {
        List {
            Section {
                LabeledContent("Chain", value: branch.chainName)
                LabeledContent("Branch", value: branch.name)
                if let address = branch.address, !address.isEmpty {
                    LabeledContent("Address", value: address)
                }
                LabeledContent("Status", value: branch.isEnabled ? "Enabled" : "Disabled")
            }
        }
        .navigationTitle(branch.displayName)
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Product Detail

struct ProductDetailView: View {
    let product: Product
    let priceHistory: [PriceObservation]

    private var sortedHistory: [PriceObservation] {
        priceHistory.sorted { $0.observedDate > $1.observedDate }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Name", value: product.name)
                if let category = product.category {
                    LabeledContent("Category", value: category)
                }
                if let unit = product.defaultUnit {
                    LabeledContent("Default unit", value: unit.rawValue)
                }
            }

            if !sortedHistory.isEmpty {
                Section("Price History") {
                    ForEach(sortedHistory) { obs in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(obs.storeBranchName)
                                    .font(.subheadline)
                                Text(obs.observedDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("kr \(NSDecimalNumber(decimal: obs.price).stringValue)")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle(product.name)
        .navigationBarTitleDisplayMode(.large)
    }
}
