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
    case createProduct, updateProduct, deleteProduct
    case createPriceObservation, updatePriceObservation, deletePriceObservation
    case createShoppingList, updateShoppingList, deleteShoppingList
    case addShoppingListItem, updateShoppingListItem, completeShoppingListItem, removeShoppingListItem
    case createRecipe, updateRecipe, deleteRecipe, addRecipeToShoppingList
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
        case .createRecipe: return "Create recipe"
        case .updateRecipe: return "Update recipe"
        case .deleteRecipe: return "Delete recipe"
        case .addRecipeToShoppingList: return "Add recipe to list"
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
        case .createPriceObservation, .updatePriceObservation: return "dollarsign.circle"
        case .deletePriceObservation: return "dollarsign.circle"
        case .createShoppingList, .updateShoppingList: return "list.bullet"
        case .deleteShoppingList: return "list.bullet"
        case .addShoppingListItem, .updateShoppingListItem: return "cart.badge.plus"
        case .completeShoppingListItem: return "checkmark.circle"
        case .removeShoppingListItem: return "cart.badge.minus"
        case .createRecipe, .updateRecipe: return "fork.knife"
        case .deleteRecipe: return "fork.knife"
        case .addRecipeToShoppingList: return "cart.fill.badge.plus"
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
        [.deleteProduct, .deletePriceObservation, .deleteShoppingList,
         .removeShoppingListItem, .deleteRecipe, .deleteStore, .deleteMemory].contains(self)
    }
}

// MARK: - Action Payload

enum ProposedActionPayload {
    case createProduct(name: String, category: String?, unit: MeasurementUnit?)
    case createPriceObservation(productName: String, storeBranchName: String, price: Decimal, quantity: Double?, unit: MeasurementUnit?, isPromotion: Bool, date: Date)
    case addShoppingListItem(listName: String, productName: String, quantity: String, notes: String?)
    case createShoppingList(name: String)
    case createStore(chainName: String, branchName: String, address: String?, isEnabled: Bool)
    case updateStore(existingStoreName: String, chainName: String?, branchName: String?, address: String?, isEnabled: Bool?)
    case deleteStore(storeName: String)
    case setStoreEnabled(storeName: String, isEnabled: Bool)
    case createMemory(summary: String, category: MemoryCategory, strength: ConstraintStrength, sensitivityLevel: SensitivityLevel)
    case changeAppSetting(key: String, value: String)
    case createRecipe(title: String, servings: Int)
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
