import Foundation

// MARK: - Proposed Action

struct ProposedAction: Identifiable {
    let id: UUID
    let type: ProposedActionType
    let summary: String
    let payload: ProposedActionPayload
    let riskLevel: RiskLevel
    let requiresConfirmation: Bool
    var validationResult: ValidationResult
    var status: ExecutionStatus
    var resultingRecordIDs: [UUID]
    var undoInfo: UndoInfo?

    init(
        id: UUID = UUID(),
        type: ProposedActionType,
        summary: String,
        payload: ProposedActionPayload,
        riskLevel: RiskLevel = .low,
        requiresConfirmation: Bool = true
    ) {
        self.id = id
        self.type = type
        self.summary = summary
        self.payload = payload
        self.riskLevel = riskLevel
        self.requiresConfirmation = requiresConfirmation
        self.validationResult = .valid
        self.status = .pending
        self.resultingRecordIDs = []
    }
}

// MARK: - Action Types

enum ProposedActionType: String {
    case createProduct, updateProduct, deleteProduct, mergeProducts
    case createPriceObservation, updatePriceObservation, deletePriceObservation
    case createShoppingList, updateShoppingList, deleteShoppingList
    case addShoppingListItem, updateShoppingListItem, completeShoppingListItem, removeShoppingListItem
    case setShoppingListStatus, optimizeShoppingList, moveShoppingListItem, substituteShoppingListItem
    case createRecipe, updateRecipe, deleteRecipe, addRecipeToShoppingList
    case setMealPlanSlot, removeMealPlanSlot, buildShoppingListFromMealPlan
    case createMatkasseBox, updateMatkasseBox, deleteMatkasseBox, addMatkasseMeal, removeMatkasseMeal
    case addProductAlias, removeProductAlias, setProductBarcode
    case confirmPriceObservation, flagCommunityPrice
    case createStore, updateStore, deleteStore, enableStore, disableStore
    case updateShoppingPreferences
    case createMemory, updateMemory, deleteMemory
    case createHousehold, inviteHouseholdMember, updateHouseholdMember
    case changeAppSetting

    var displayName: String {
        switch self {
        case .createProduct: return "Add product"
        case .updateProduct: return "Update product"
        case .deleteProduct: return "Delete product"
        case .mergeProducts: return "Merge products"
        case .createPriceObservation: return "Add price"
        case .updatePriceObservation: return "Update price"
        case .deletePriceObservation: return "Delete price"
        case .createShoppingList: return "Create list"
        case .updateShoppingList: return "Update list"
        case .deleteShoppingList: return "Delete list"
        case .addShoppingListItem: return "Add to list"
        case .updateShoppingListItem: return "Update item"
        case .completeShoppingListItem: return "Complete item"
        case .removeShoppingListItem: return "Remove from list"
        case .setShoppingListStatus: return "Change list status"
        case .optimizeShoppingList: return "Optimize list"
        case .moveShoppingListItem: return "Move item"
        case .substituteShoppingListItem: return "Substitute item"
        case .createRecipe: return "Create recipe"
        case .updateRecipe: return "Update recipe"
        case .deleteRecipe: return "Delete recipe"
        case .addRecipeToShoppingList: return "Add recipe to list"
        case .setMealPlanSlot: return "Plan meal"
        case .removeMealPlanSlot: return "Remove planned meal"
        case .buildShoppingListFromMealPlan: return "Build shopping list from meal plan"
        case .createMatkasseBox: return "Add matkasse box"
        case .updateMatkasseBox: return "Update matkasse box"
        case .deleteMatkasseBox: return "Delete matkasse box"
        case .addMatkasseMeal: return "Add matkasse meal"
        case .removeMatkasseMeal: return "Remove matkasse meal"
        case .addProductAlias: return "Add product alias"
        case .removeProductAlias: return "Remove product alias"
        case .setProductBarcode: return "Set product barcode"
        case .confirmPriceObservation: return "Confirm price"
        case .flagCommunityPrice: return "Flag community price"
        case .createStore: return "Add store"
        case .updateStore: return "Update store"
        case .deleteStore: return "Delete store"
        case .enableStore: return "Enable store"
        case .disableStore: return "Disable store"
        case .updateShoppingPreferences: return "Update preferences"
        case .createMemory: return "Remember"
        case .updateMemory: return "Update memory"
        case .deleteMemory: return "Forget"
        case .createHousehold: return "Create household"
        case .inviteHouseholdMember: return "Invite member"
        case .updateHouseholdMember: return "Update member"
        case .changeAppSetting: return "Change setting"
        }
    }

    var systemImage: String {
        switch self {
        case .createProduct, .updateProduct: return "tag"
        case .deleteProduct: return "tag.slash"
        case .mergeProducts: return "arrow.triangle.merge"
        case .createPriceObservation, .updatePriceObservation: return "dollarsign.circle"
        case .deletePriceObservation: return "dollarsign.circle"
        case .createShoppingList, .updateShoppingList: return "list.bullet"
        case .deleteShoppingList: return "list.bullet"
        case .addShoppingListItem, .updateShoppingListItem: return "cart.badge.plus"
        case .completeShoppingListItem: return "checkmark.circle"
        case .removeShoppingListItem: return "cart.badge.minus"
        case .setShoppingListStatus: return "arrow.triangle.2.circlepath"
        case .optimizeShoppingList: return "wand.and.sparkles"
        case .moveShoppingListItem: return "arrow.left.arrow.right"
        case .substituteShoppingListItem: return "arrow.triangle.2.circlepath.circle"
        case .createRecipe, .updateRecipe: return "fork.knife"
        case .deleteRecipe: return "fork.knife"
        case .addRecipeToShoppingList, .buildShoppingListFromMealPlan: return "cart.fill.badge.plus"
        case .setMealPlanSlot: return "calendar.badge.plus"
        case .removeMealPlanSlot: return "calendar.badge.minus"
        case .createMatkasseBox, .updateMatkasseBox, .addMatkasseMeal: return "shippingbox"
        case .deleteMatkasseBox, .removeMatkasseMeal: return "shippingbox"
        case .addProductAlias, .removeProductAlias, .setProductBarcode: return "tag"
        case .confirmPriceObservation: return "checkmark.seal"
        case .flagCommunityPrice: return "flag"
        case .createStore, .updateStore, .enableStore: return "storefront"
        case .deleteStore, .disableStore: return "storefront"
        case .updateShoppingPreferences: return "slider.horizontal.3"
        case .createMemory, .updateMemory: return "brain.head.profile"
        case .deleteMemory: return "brain.head.profile"
        case .createHousehold, .inviteHouseholdMember, .updateHouseholdMember: return "person.3"
        case .changeAppSetting: return "gearshape"
        }
    }

    var isMemoryAction: Bool {
        [.createMemory, .updateMemory, .deleteMemory].contains(self)
    }

    var isDestructive: Bool {
        [.deleteProduct, .mergeProducts, .deletePriceObservation, .deleteShoppingList,
         .removeShoppingListItem, .deleteRecipe, .removeMealPlanSlot, .deleteStore, .deleteMemory,
         .deleteMatkasseBox, .removeMatkasseMeal].contains(self)
    }
}

// MARK: - Action Payload

enum ProposedActionPayload {
    case createProduct(name: String, category: String?, unit: MeasurementUnit?)
    case updateProduct(existingName: String, newName: String?, category: String?, unit: MeasurementUnit?)
    case deleteProduct(name: String)
    case mergeProducts(sourceProductName: String, targetProductName: String)
    case createPriceObservation(productName: String, storeBranchName: String, price: Decimal, quantity: Double?, unit: MeasurementUnit?, isPromotion: Bool, date: Date)
    case updatePriceObservation(productName: String, storeBranchName: String?, newPrice: Decimal?, newQuantity: Double?, newUnit: MeasurementUnit?)
    case deletePriceObservation(productName: String, storeBranchName: String?)
    case confirmPriceObservation(productName: String, storeBranchName: String?)
    case flagCommunityPrice(productName: String, storeBranchName: String?)
    case addProductAlias(productName: String, alias: String)
    case removeProductAlias(productName: String, alias: String)
    case setProductBarcode(productName: String, barcode: String)
    case addShoppingListItem(listName: String, productName: String, quantity: String, notes: String?)
    case createShoppingList(name: String)
    case updateShoppingList(existingListName: String, newName: String?, plannedDate: Date?)
    case deleteShoppingList(listName: String)
    case updateShoppingListItem(listName: String, productName: String, newQuantity: String?, newNotes: String?)
    case completeShoppingListItem(listName: String, productName: String, isCompleted: Bool)
    case removeShoppingListItem(listName: String, productName: String)
    case setShoppingListStatus(listName: String, status: String)
    case optimizeShoppingList(listName: String)
    case moveShoppingListItem(listName: String, productName: String, storeBranchName: String)
    case substituteShoppingListItem(listName: String, productName: String, newProductName: String)
    case addRecipeToShoppingList(recipeName: String, listName: String)
    case createStore(chainName: String, branchName: String, address: String?, isEnabled: Bool)
    case updateStore(existingStoreName: String, chainName: String?, branchName: String?, address: String?, isEnabled: Bool?)
    case deleteStore(storeName: String)
    case setStoreEnabled(storeName: String, isEnabled: Bool)
    case createMemory(summary: String, category: MemoryCategory, strength: ConstraintStrength, sensitivityLevel: SensitivityLevel)
    case changeAppSetting(key: String, value: String)
    case createRecipe(title: String, servings: Int)
    case updateRecipe(existingTitle: String, newTitle: String?, description: String?, servings: Int?)
    case deleteRecipe(title: String)
    case setMealPlanSlot(date: Date, mealType: String, recipeTitle: String?, freeformText: String?, isEatingOut: Bool, isLeftover: Bool)
    case removeMealPlanSlot(date: Date, mealType: String)
    case buildShoppingListFromMealPlan(weekStartDate: Date?, oneListPerWeek: Bool)
    case createMatkasseBox(provider: String, deliveryWeek: Date?, numberOfMeals: Int?, servingsPerMeal: Int?, price: Decimal?, notes: String?)
    case updateMatkasseBox(existingProvider: String, newProvider: String?, deliveryWeek: Date?, numberOfMeals: Int?, servingsPerMeal: Int?, price: Decimal?, notes: String?)
    case deleteMatkasseBox(provider: String)
    case addMatkasseMeal(boxProvider: String, mealTitle: String)
    case removeMatkasseMeal(boxProvider: String, mealTitle: String)
    case generic(description: String)
}

// MARK: - Supporting Types

enum RiskLevel {
    case low, medium, high

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

enum ExecutionStatus {
    case pending, approved, rejected, executing, completed, failed

    var isTerminal: Bool {
        switch self {
        case .completed, .rejected, .failed: return true
        default: return false
        }
    }
}

enum ValidationResult {
    case valid
    case invalid(reason: String)
    case warning(message: String)

    var isValid: Bool {
        if case .invalid = self { return false }
        return true
    }
}

struct UndoInfo {
    let description: String
    let affectedRecordIDs: [UUID]
}

// MARK: - Activity Tag

struct ActivityTag: Identifiable {
    let id: UUID
    let actionType: ProposedActionType
    let summary: String
    let timestamp: Date
    let affectedRecordIDs: [UUID]

    init(id: UUID = UUID(), from action: ProposedAction) {
        self.id = id
        self.actionType = action.type
        self.summary = action.summary
        self.timestamp = Date()
        self.affectedRecordIDs = action.resultingRecordIDs
    }

    init(id: UUID, actionType: ProposedActionType, summary: String, timestamp: Date, affectedRecordIDs: [UUID]) {
        self.id = id
        self.actionType = actionType
        self.summary = summary
        self.timestamp = timestamp
        self.affectedRecordIDs = affectedRecordIDs
    }
}
