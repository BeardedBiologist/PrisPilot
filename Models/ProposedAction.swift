import Foundation

// MARK: - Proposed Action

struct ProposedAction: Identifiable, Codable {
    let id: UUID
    let type: ProposedActionType
    var summary: String
    var payload: ProposedActionPayload
    let riskLevel: RiskLevel
    let requiresConfirmation: Bool
    var validationResult: ValidationResult
    var status: ExecutionStatus
    var resultingRecordIDs: [UUID]
    var undoSnapshot: UndoSnapshot?

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

enum ProposedActionType: String, Codable {
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

    var domain: ActionDomain {
        switch self {
        case .createProduct, .updateProduct, .deleteProduct, .mergeProducts,
             .addProductAlias, .removeProductAlias, .setProductBarcode,
             .createPriceObservation, .updatePriceObservation, .deletePriceObservation,
             .confirmPriceObservation, .flagCommunityPrice:
            return .prices
        case .createShoppingList, .updateShoppingList, .deleteShoppingList,
             .addShoppingListItem, .updateShoppingListItem, .completeShoppingListItem,
             .removeShoppingListItem, .setShoppingListStatus, .optimizeShoppingList,
             .moveShoppingListItem, .substituteShoppingListItem, .addRecipeToShoppingList,
             .buildShoppingListFromMealPlan:
            return .shopping
        case .createRecipe, .updateRecipe, .deleteRecipe,
             .setMealPlanSlot, .removeMealPlanSlot,
             .createMatkasseBox, .updateMatkasseBox, .deleteMatkasseBox,
             .addMatkasseMeal, .removeMatkasseMeal:
            return .meals
        case .createStore, .updateStore, .deleteStore, .enableStore, .disableStore:
            return .stores
        case .createMemory, .updateMemory, .deleteMemory:
            return .memory
        case .updateShoppingPreferences, .changeAppSetting,
             .createHousehold, .inviteHouseholdMember, .updateHouseholdMember:
            return .settings
        }
    }

    var expectsAffectedRecordIDs: Bool {
        switch self {
        case .setMealPlanSlot, .removeMealPlanSlot, .changeAppSetting:
            return false
        default:
            return true
        }
    }
}

// MARK: - Action Payload

enum ProposedActionPayload: Codable {
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
    case updateMemory(existingSummary: String, newSummary: String?, category: MemoryCategory?, strength: ConstraintStrength?, sensitivityLevel: SensitivityLevel?)
    case deleteMemory(summary: String)
    case createHousehold(name: String, ownerDisplayName: String?)
    case inviteHouseholdMember(email: String?)
    case updateHouseholdMember(userID: String, displayName: String?, role: HouseholdRole?)
    case changeAppSetting(key: String, value: String)
    case createRecipe(title: String, description: String?, servings: Int, ingredients: [RecipeIngredient], steps: [String], tags: [String], author: String?, prepTimeMinutes: Int?, cookTimeMinutes: Int?)
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

enum RiskLevel: Codable {
    case low, medium, high

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

enum ActionDomain: String, Hashable, Codable {
    case shopping = "Shopping"
    case prices = "Prices"
    case meals = "Meals"
    case stores = "Stores"
    case memory = "Memory"
    case settings = "Settings"

    var systemImage: String {
        switch self {
        case .shopping: return "cart.fill"
        case .prices: return "tag.fill"
        case .meals: return "fork.knife"
        case .stores: return "storefront.fill"
        case .memory: return "brain.head.profile"
        case .settings: return "gearshape.fill"
        }
    }
}

enum ExecutionStatus: Equatable, Codable {
    case pending, approved, rejected, executing, completed, failed

    var isTerminal: Bool {
        switch self {
        case .completed, .rejected, .failed: return true
        default: return false
        }
    }
}

enum ValidationResult: Codable {
    case valid
    case invalid(reason: String)
    case warning(message: String)
    case requiresClarification(question: String)

    var isValid: Bool {
        switch self {
        case .valid, .warning:
            return true
        case .invalid, .requiresClarification:
            return false
        }
    }

    var clarificationQuestion: String? {
        if case .requiresClarification(let question) = self {
            return question
        }
        return nil
    }
}

// MARK: - Undo Snapshot

/// Before-state captured just before an update or delete executes.
/// Stored in ActivityTag so undoActivityTag can reverse the change.
enum UndoSnapshot: Codable {
    // Field-level snapshots for update actions
    case productFields(id: UUID, name: String, category: String?, unit: MeasurementUnit?)
    case recipeFields(id: UUID, title: String, description: String?, servings: Int)
    case shoppingListFields(id: UUID, name: String, plannedDate: Date?)
    case shoppingListStatusFields(id: UUID, status: ListStatus, completedAt: Date?, archivedAt: Date?)
    case shoppingListItemFields(listID: UUID, itemID: UUID, quantity: String, notes: String?)
    case shoppingListItemState(listID: UUID, item: ShoppingListItem)
    case priceObservationFields(id: UUID, price: Decimal, quantity: Double?, unit: MeasurementUnit?)
    case productMetadataFields(id: UUID, aliases: [String], barcode: String?)
    case storeBranchFields(id: UUID, chainName: String, branchName: String, address: String?, isEnabled: Bool)
    case matkasseBoxFields(id: UUID, provider: String, deliveryWeekStartDate: Date, numberOfMeals: Int, servingsPerMeal: Int, price: Decimal?, notes: String?)
    case communityContributionFlag(id: UUID, wasFlagged: Bool)
    // Full record snapshots for delete/remove actions
    case deletedShoppingList(ShoppingList)
    case createdShoppingList(id: UUID)
    case deletedShoppingListItem(listID: UUID, item: ShoppingListItem)
    case deletedProduct(Product)
    case deletedRecipe(Recipe)
    case deletedPriceObservation(PriceObservation)
    case createdCommunityContribution(id: UUID)
    case deletedStoreBranch(StoreBranch)
    case deletedMatkasseBox(MatkasseBox)
    case deletedMatkasseMeal(boxID: UUID, meal: MatkasseMeal)
    case deletedMemory(AIMemory)
    case householdState(household: Household?, invitations: [Invitation])
    case createdInvitation(id: UUID)
    // Meal plan snapshots
    case addedMealPlanSlot(date: Date, mealType: MealType)
    case overwrittenMealPlanSlot(slot: MealPlanSlot)
    case clearedMealPlanSlot(slot: MealPlanSlot)
}

// MARK: - Execution Result

struct ActionExecutionResult {
    let affectedRecordIDs: [UUID]
    let undoSnapshot: UndoSnapshot?

    init(ids: [UUID], undo: UndoSnapshot? = nil) {
        self.affectedRecordIDs = ids
        self.undoSnapshot = undo
    }

    static let empty = ActionExecutionResult(ids: [])
}

// MARK: - Execution Plan

struct ActionExecutionPlan {
    enum DependencyMode {
        case independent
        case allOrNothing
    }
    var actions: [ProposedAction]
    let mode: DependencyMode

    init(actions: [ProposedAction], mode: DependencyMode = .independent) {
        self.actions = actions
        self.mode = mode
    }
}

struct ActionPlanResult {
    struct ActionOutcome {
        let actionID: UUID
        let affectedRecordIDs: [UUID]
        let undoSnapshot: UndoSnapshot?
        let failureReason: String?
        let skippedReason: String?
        var succeeded: Bool { failureReason == nil && skippedReason == nil }
    }
    let outcomes: [ActionOutcome]
    var allSucceeded: Bool { outcomes.allSatisfy(\.succeeded) }
    var anyFailed: Bool { outcomes.contains { $0.failureReason != nil } }
    var anySkipped: Bool { outcomes.contains { $0.skippedReason != nil } }
}

// MARK: - Activity Tag

struct ActivityTag: Identifiable, Codable {
    let id: UUID
    let actionType: ProposedActionType
    let summary: String
    let timestamp: Date
    let affectedRecordIDs: [UUID]
    let undoSnapshot: UndoSnapshot?

    init(id: UUID = UUID(), from action: ProposedAction) {
        self.id = id
        self.actionType = action.type
        self.summary = action.summary
        self.timestamp = Date()
        self.affectedRecordIDs = action.resultingRecordIDs
        self.undoSnapshot = action.undoSnapshot
    }

    init(id: UUID = UUID(), actionType: ProposedActionType, summary: String, timestamp: Date = Date(), affectedRecordIDs: [UUID] = [], undoSnapshot: UndoSnapshot? = nil) {
        self.id = id
        self.actionType = actionType
        self.summary = summary
        self.timestamp = timestamp
        self.affectedRecordIDs = affectedRecordIDs
        self.undoSnapshot = undoSnapshot
    }
}
