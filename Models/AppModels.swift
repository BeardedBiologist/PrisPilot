import Foundation

// MARK: - Shared Enums

enum DataScope: String, Codable, CaseIterable {
    case personal = "Personal"
    case household = "Household"
    case session = "Session"
}

enum MeasurementUnit: String, Codable, CaseIterable, Identifiable {
    case grams = "g"
    case kilograms = "kg"
    case millilitres = "ml"
    case litres = "l"
    case pieces = "stk"
    case packs = "pk"

    var id: String { rawValue }
}

// MARK: - Currency & Country

struct Currency: Codable, Hashable {
    var code: String
    var symbol: String
    var name: String

    static let nok = Currency(code: "NOK", symbol: "kr", name: "Norwegian Krone")
    static let eur = Currency(code: "EUR", symbol: "€", name: "Euro")
    static let usd = Currency(code: "USD", symbol: "$", name: "US Dollar")
    static let gbp = Currency(code: "GBP", symbol: "£", name: "British Pound")
}

struct Country: Codable, Identifiable, Hashable {
    let id: UUID
    var code: String
    var name: String
    var defaultCurrency: Currency

    static let norway = Country(id: UUID(), code: "NO", name: "Norway", defaultCurrency: .nok)
}

// MARK: - Stores

struct SupermarketChain: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var countryCode: String
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String, countryCode: String = "NO", isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.countryCode = countryCode
        self.isEnabled = isEnabled
    }
}

struct StoreBranch: Codable, Identifiable, Hashable {
    let id: UUID
    var chainID: UUID
    var chainName: String
    var name: String
    var address: String?
    var isEnabled: Bool

    init(id: UUID = UUID(), chainID: UUID, chainName: String, name: String, address: String? = nil, isEnabled: Bool = true) {
        self.id = id
        self.chainID = chainID
        self.chainName = chainName
        self.name = name
        self.address = address
        self.isEnabled = isEnabled
    }

    var displayName: String { "\(chainName) \(name)" }
}

// MARK: - Products

struct Product: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var category: String?
    var defaultUnit: MeasurementUnit?
    var aliases: [String]
    var createdAt: Date

    init(id: UUID = UUID(), name: String, category: String? = nil, defaultUnit: MeasurementUnit? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.defaultUnit = defaultUnit
        self.aliases = []
        self.createdAt = Date()
    }
}

// MARK: - Prices

struct PriceObservation: Codable, Identifiable {
    let id: UUID
    var productID: UUID
    var productName: String
    var storeBranchID: UUID
    var storeBranchName: String
    var price: Decimal
    var currency: Currency
    var quantity: Double?
    var unit: MeasurementUnit?
    var isPromotion: Bool
    var promotionEndDate: Date?
    var observedDate: Date
    var source: PriceSource
    var scope: DataScope
    var confidence: PriceConfidence
    var createdAt: Date

    init(
        id: UUID = UUID(),
        productID: UUID,
        productName: String,
        storeBranchID: UUID,
        storeBranchName: String,
        price: Decimal,
        currency: Currency = .nok,
        quantity: Double? = nil,
        unit: MeasurementUnit? = nil,
        isPromotion: Bool = false,
        observedDate: Date = Date(),
        source: PriceSource = .manual,
        scope: DataScope = .personal
    ) {
        self.id = id
        self.productID = productID
        self.productName = productName
        self.storeBranchID = storeBranchID
        self.storeBranchName = storeBranchName
        self.price = price
        self.currency = currency
        self.quantity = quantity
        self.unit = unit
        self.isPromotion = isPromotion
        self.observedDate = observedDate
        self.source = source
        self.scope = scope
        self.confidence = .high
        self.createdAt = Date()
    }
}

enum PriceSource: String, Codable {
    case manual = "Manual"
    case chat = "Chat"
    case receiptScan = "Receipt Scan"
    case barcodeScan = "Barcode Scan"
    case community = "Community"
}

enum PriceConfidence: String, Codable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    case unconfirmed = "Unconfirmed"
}

// MARK: - Shopping Lists

struct ShoppingList: Codable, Identifiable {
    let id: UUID
    var name: String
    var scope: DataScope
    var status: ListStatus
    var items: [ShoppingListItem]
    var plannedDate: Date?
    var estimatedTotal: Decimal?
    var actualTotal: Decimal?
    var createdAt: Date

    init(id: UUID = UUID(), name: String, scope: DataScope = .personal) {
        self.id = id
        self.name = name
        self.scope = scope
        self.status = .active
        self.items = []
        self.createdAt = Date()
    }
}

struct ShoppingListItem: Codable, Identifiable {
    let id: UUID
    var listID: UUID
    var productName: String
    var productID: UUID?
    var requestedQuantity: String
    var preferredVariant: String?
    var assignedStoreBranch: String?
    var estimatedPrice: Decimal?
    var actualPrice: Decimal?
    var isCompleted: Bool
    var notes: String?
    var addedAt: Date

    init(id: UUID = UUID(), listID: UUID, productName: String, requestedQuantity: String = "1") {
        self.id = id
        self.listID = listID
        self.productName = productName
        self.requestedQuantity = requestedQuantity
        self.isCompleted = false
        self.addedAt = Date()
    }
}

enum ListStatus: String, Codable {
    case active = "Active"
    case completed = "Completed"
    case archived = "Archived"
}

// MARK: - Recipes

struct Recipe: Codable, Identifiable {
    let id: UUID
    var title: String
    var description: String?
    var servings: Int
    var ingredients: [RecipeIngredient]
    var steps: [String]
    var tags: [String]
    var scope: DataScope
    var isFavorite: Bool
    var createdAt: Date

    init(id: UUID = UUID(), title: String, servings: Int = 4) {
        self.id = id
        self.title = title
        self.servings = servings
        self.ingredients = []
        self.steps = []
        self.tags = []
        self.scope = .personal
        self.isFavorite = false
        self.createdAt = Date()
    }
}

struct RecipeIngredient: Codable, Identifiable {
    let id: UUID
    var productName: String
    var quantity: Double
    var unit: MeasurementUnit
    var notes: String?

    init(id: UUID = UUID(), productName: String, quantity: Double, unit: MeasurementUnit) {
        self.id = id
        self.productName = productName
        self.quantity = quantity
        self.unit = unit
    }
}

// MARK: - AI Memory

struct AIMemory: Codable, Identifiable {
    let id: UUID
    var summary: String
    var category: MemoryCategory
    var subject: String?
    var scope: DataScope
    var strength: ConstraintStrength
    var isExplicitlyStated: Bool
    var confidence: Double
    var sensitivityLevel: SensitivityLevel
    var isActive: Bool
    var createdAt: Date
    var lastConfirmedAt: Date?
    var lastUsedAt: Date?

    init(
        id: UUID = UUID(),
        summary: String,
        category: MemoryCategory,
        scope: DataScope = .personal,
        strength: ConstraintStrength = .preference,
        isExplicitlyStated: Bool = true,
        confidence: Double = 0.9,
        sensitivityLevel: SensitivityLevel = .standard
    ) {
        self.id = id
        self.summary = summary
        self.category = category
        self.scope = scope
        self.strength = strength
        self.isExplicitlyStated = isExplicitlyStated
        self.confidence = confidence
        self.sensitivityLevel = sensitivityLevel
        self.isActive = true
        self.createdAt = Date()
    }
}

enum MemoryCategory: String, Codable, CaseIterable {
    case hardRequirement = "Hard Requirement"
    case preference = "Preference"
    case habit = "Habit"
    case decisionPattern = "Decision Pattern"

    var systemImage: String {
        switch self {
        case .hardRequirement: return "exclamationmark.shield.fill"
        case .preference: return "heart.fill"
        case .habit: return "arrow.clockwise"
        case .decisionPattern: return "brain.head.profile"
        }
    }
}

enum ConstraintStrength: String, Codable {
    case absolute = "Absolute"
    case strong = "Strong"
    case preference = "Preference"
    case weak = "Weak"
}

enum SensitivityLevel: String, Codable {
    case standard = "Standard"
    case sensitive = "Sensitive"
    case health = "Health"
}

// MARK: - App Settings

struct AppSettings: Codable {
    var country: Country
    var currency: Currency
    var language: String
    var maxSupermarketCount: Int
    var minimumAdditionalStoreSavings: Decimal
    var cheapestDefinition: CheapestDefinition
    var onboardingCompleted: Bool

    static var defaultSettings: AppSettings {
        AppSettings(
            country: .norway,
            currency: .nok,
            language: "en",
            maxSupermarketCount: 2,
            minimumAdditionalStoreSavings: Decimal(20),
            cheapestDefinition: .bestPracticalTrip,
            onboardingCompleted: false
        )
    }
}

enum CheapestDefinition: String, Codable, CaseIterable {
    case absoluteCheapest = "Absolute Cheapest"
    case bestPracticalTrip = "Best Practical Trip"
    case oneStoreShop = "One-Store Shop"
    case preferredStoresOnly = "Preferred Stores Only"
    case custom = "Custom"
}
