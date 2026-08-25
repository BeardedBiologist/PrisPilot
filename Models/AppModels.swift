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
    var distanceFromHomeKm: Double?
    var latitude: Double?
    var longitude: Double?
    var isEnabled: Bool

    init(id: UUID = UUID(), chainID: UUID, chainName: String, name: String, address: String? = nil, distanceFromHomeKm: Double? = nil, latitude: Double? = nil, longitude: Double? = nil, isEnabled: Bool = true) {
        self.id = id
        self.chainID = chainID
        self.chainName = chainName
        self.name = name
        self.address = address
        self.distanceFromHomeKm = distanceFromHomeKm
        self.latitude = latitude
        self.longitude = longitude
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
    var barcode: String?
    var aliases: [String]
    var createdAt: Date

    init(id: UUID = UUID(), name: String, category: String? = nil, defaultUnit: MeasurementUnit? = nil, barcode: String? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.defaultUnit = defaultUnit
        self.barcode = barcode
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
    var priceKind: PriceKind?
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
        priceKind: PriceKind? = nil,
        promotionEndDate: Date? = nil,
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
        self.priceKind = priceKind
        self.promotionEndDate = promotionEndDate
        self.observedDate = observedDate
        self.source = source
        self.scope = scope
        self.confidence = .high
        self.createdAt = Date()
    }

    var isStale: Bool {
        ageInDays > 30
    }

    var isPromoExpired: Bool {
        guard isPromotion, let end = promotionEndDate else { return false }
        return end < Date()
    }

    var ageInDays: Int {
        Calendar.current.dateComponents([.day], from: observedDate, to: Date()).day ?? 0
    }

    var freshnessAdjustedConfidence: PriceConfidence {
        if isPromoExpired { return .unconfirmed }
        switch ageInDays {
        case 0...30:
            return confidence
        case 31...60:
            return confidence.reduced()
        case 61...90:
            return confidence.reduced().reduced()
        default:
            return .unconfirmed
        }
    }
}

struct CommunityContribution: Codable, Identifiable {
    let id: UUID
    var sourceObservationID: UUID
    var anonymousContributorHash: String
    var productID: UUID
    var productName: String
    var storeBranchID: UUID
    var storeBranchName: String
    var price: Decimal
    var currency: Currency
    var observedDate: Date
    var submittedAt: Date?
    var isFlagged: Bool
    var createdAt: Date

    init(id: UUID = UUID(), sourceObservation: PriceObservation, anonymousContributorHash: String) {
        self.id = id
        self.sourceObservationID = sourceObservation.id
        self.anonymousContributorHash = anonymousContributorHash
        self.productID = sourceObservation.productID
        self.productName = sourceObservation.productName
        self.storeBranchID = sourceObservation.storeBranchID
        self.storeBranchName = sourceObservation.storeBranchName
        self.price = sourceObservation.price
        self.currency = sourceObservation.currency
        self.observedDate = sourceObservation.observedDate
        self.submittedAt = nil
        self.isFlagged = false
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

enum PriceKind: String, Codable, CaseIterable, Identifiable {
    case regular = "Regular"
    case member = "Member"
    case loyalty = "Loyalty"

    var id: String { rawValue }
}

enum PriceConfidence: String, Codable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    case unconfirmed = "Unconfirmed"

    var rank: Int {
        switch self {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        case .unconfirmed: return 0
        }
    }

    func reduced() -> PriceConfidence {
        switch self {
        case .high: return .medium
        case .medium: return .low
        case .low, .unconfirmed: return .unconfirmed
        }
    }
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
    var completedAt: Date?
    var archivedAt: Date?
    var optimizationSnapshot: OptimizationSnapshot?

    init(id: UUID = UUID(), name: String, scope: DataScope = .personal) {
        self.id = id
        self.name = name
        self.scope = scope
        self.status = .active
        self.items = []
        self.createdAt = Date()
    }
}

/// Result of the last time `AppStore.optimizeShoppingList(_:)` ran for this
/// list, kept alongside the list so overview cards can show store count /
/// savings without recomputing the optimizer.
struct OptimizationSnapshot: Codable {
    var chosenStores: [String]
    var estimatedOneStoreTotal: Decimal
    var optimizedTotal: Decimal
    var savings: Decimal
    var unpricedItemCount: Int
    var optimizationDate: Date
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
    /// The exact `PriceObservation` the optimizer (or a manual reassignment)
    /// used to set `estimatedPrice`, distinct from `assignedStoreBranch`
    /// (a display string) so a specific price record can be traced back to.
    var selectedPriceObservationID: UUID?
    var substituteCandidateNames: [String]?

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
    case planned = "Planned"
    case completed = "Completed"
    case archived = "Archived"
}

// MARK: - Households

struct Household: Codable, Identifiable {
    let id: UUID
    var name: String
    var ownerUserID: String
    var members: [HouseholdMember]
    var createdAt: Date

    init(id: UUID = UUID(), name: String, ownerUserID: String, ownerDisplayName: String? = nil) {
        self.id = id
        self.name = name
        self.ownerUserID = ownerUserID
        self.members = [
            HouseholdMember(userID: ownerUserID, displayName: ownerDisplayName, role: .owner)
        ]
        self.createdAt = Date()
    }
}

struct HouseholdMember: Codable, Identifiable {
    let id: UUID
    var userID: String
    var displayName: String?
    var role: HouseholdRole
    var joinedAt: Date

    init(id: UUID = UUID(), userID: String, displayName: String? = nil, role: HouseholdRole, joinedAt: Date = Date()) {
        self.id = id
        self.userID = userID
        self.displayName = displayName
        self.role = role
        self.joinedAt = joinedAt
    }
}

enum HouseholdRole: String, Codable {
    case owner = "Owner"
    case member = "Member"
}

struct Invitation: Codable, Identifiable {
    let id: UUID
    var householdID: UUID
    var inviterUserID: String
    var inviteeEmail: String?
    var shareCode: String
    var status: InvitationStatus
    var expiresAt: Date
    var createdAt: Date

    init(
        id: UUID = UUID(),
        householdID: UUID,
        inviterUserID: String,
        inviteeEmail: String? = nil,
        shareCode: String = Invitation.generateShareCode(),
        status: InvitationStatus = .pending,
        expiresAt: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.householdID = householdID
        self.inviterUserID = inviterUserID
        self.inviteeEmail = inviteeEmail
        self.shareCode = shareCode
        self.status = status
        self.expiresAt = expiresAt
        self.createdAt = createdAt
    }

    static func generateShareCode() -> String {
        let characters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).compactMap { _ in characters.randomElement() })
    }

    var isExpired: Bool {
        expiresAt < Date()
    }
}

enum InvitationStatus: String, Codable {
    case pending = "Pending"
    case accepted = "Accepted"
    case declined = "Declined"
    case expired = "Expired"
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

enum ConstraintStrength: String, Codable, CaseIterable {
    case absolute = "Absolute"
    case strong = "Strong"
    case preference = "Preference"
    case weak = "Weak"
}

enum SensitivityLevel: String, Codable, CaseIterable {
    case standard = "Standard"
    case sensitive = "Sensitive"
    case health = "Health"
}

// MARK: - AI Permissions

enum AIPermissionArea: String, Codable, CaseIterable, Identifiable {
    case shoppingLists = "Shopping lists"
    case products = "Products"
    case prices = "Prices"
    case recipes = "Recipes"
    case memory = "AI Memory"
    case household = "Household"
    case settings = "Settings"

    var id: String { rawValue }
}

enum AIPermissionOperation: String, Codable, CaseIterable, Identifiable {
    case view = "View"
    case create = "Create"
    case edit = "Edit"
    case delete = "Delete"

    var id: String { rawValue }
}

enum AIPermissionMode: String, Codable, CaseIterable, Identifiable {
    case notAllowed = "Not allowed"
    case alwaysAsk = "Always ask"
    case automaticallyAllow = "Automatically allow"
    case automaticallyAllowForConversation = "Automatically allow for this conversation"

    var id: String { rawValue }
}

// MARK: - App Settings

struct AppSettings: Codable {
    var country: Country
    var currency: Currency
    var language: String
    var maxSupermarketCount: Int
    var minimumAdditionalStoreSavings: Decimal
    var travelCostPerKilometer: Decimal
    var fixedStoreVisitCost: Decimal
    var cheapestDefinition: CheapestDefinition
    var participatesInCommunityPricing: Bool
    var anonymousCommunityContributorID: String
    var onboardingCompleted: Bool
    var aiPermissionModes: [String: AIPermissionMode]

    init(
        country: Country,
        currency: Currency,
        language: String,
        maxSupermarketCount: Int,
        minimumAdditionalStoreSavings: Decimal,
        travelCostPerKilometer: Decimal = Decimal(0),
        fixedStoreVisitCost: Decimal = Decimal(0),
        cheapestDefinition: CheapestDefinition,
        participatesInCommunityPricing: Bool = false,
        anonymousCommunityContributorID: String = UUID().uuidString,
        onboardingCompleted: Bool,
        aiPermissionModes: [String: AIPermissionMode] = AppSettings.defaultAIPermissionModes
    ) {
        self.country = country
        self.currency = currency
        self.language = language
        self.maxSupermarketCount = maxSupermarketCount
        self.minimumAdditionalStoreSavings = minimumAdditionalStoreSavings
        self.travelCostPerKilometer = travelCostPerKilometer
        self.fixedStoreVisitCost = fixedStoreVisitCost
        self.cheapestDefinition = cheapestDefinition
        self.participatesInCommunityPricing = participatesInCommunityPricing
        self.anonymousCommunityContributorID = anonymousCommunityContributorID
        self.onboardingCompleted = onboardingCompleted
        self.aiPermissionModes = aiPermissionModes
    }

    enum CodingKeys: String, CodingKey {
        case country
        case currency
        case language
        case maxSupermarketCount
        case minimumAdditionalStoreSavings
        case travelCostPerKilometer
        case fixedStoreVisitCost
        case cheapestDefinition
        case participatesInCommunityPricing
        case anonymousCommunityContributorID
        case onboardingCompleted
        case aiPermissionModes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        country = try container.decode(Country.self, forKey: .country)
        currency = try container.decode(Currency.self, forKey: .currency)
        language = try container.decode(String.self, forKey: .language)
        maxSupermarketCount = try container.decode(Int.self, forKey: .maxSupermarketCount)
        minimumAdditionalStoreSavings = try container.decode(Decimal.self, forKey: .minimumAdditionalStoreSavings)
        travelCostPerKilometer = try container.decodeIfPresent(Decimal.self, forKey: .travelCostPerKilometer) ?? Decimal(0)
        fixedStoreVisitCost = try container.decodeIfPresent(Decimal.self, forKey: .fixedStoreVisitCost) ?? Decimal(0)
        cheapestDefinition = try container.decode(CheapestDefinition.self, forKey: .cheapestDefinition)
        participatesInCommunityPricing = try container.decodeIfPresent(Bool.self, forKey: .participatesInCommunityPricing) ?? false
        anonymousCommunityContributorID = try container.decodeIfPresent(String.self, forKey: .anonymousCommunityContributorID) ?? UUID().uuidString
        onboardingCompleted = try container.decode(Bool.self, forKey: .onboardingCompleted)
        aiPermissionModes = try container.decodeIfPresent([String: AIPermissionMode].self, forKey: .aiPermissionModes) ?? Self.defaultAIPermissionModes
    }

    static var defaultSettings: AppSettings {
        AppSettings(
            country: .norway,
            currency: .nok,
            language: "en",
            maxSupermarketCount: 2,
            minimumAdditionalStoreSavings: Decimal(20),
            travelCostPerKilometer: Decimal(0),
            fixedStoreVisitCost: Decimal(0),
            cheapestDefinition: .bestPracticalTrip,
            participatesInCommunityPricing: false,
            anonymousCommunityContributorID: UUID().uuidString,
            onboardingCompleted: false
        )
    }

    static var defaultAIPermissionModes: [String: AIPermissionMode] {
        var modes: [String: AIPermissionMode] = [:]
        for area in AIPermissionArea.allCases {
            modes[permissionKey(area: area, operation: .view)] = .automaticallyAllow
            modes[permissionKey(area: area, operation: .create)] = .alwaysAsk
            modes[permissionKey(area: area, operation: .edit)] = .alwaysAsk
            modes[permissionKey(area: area, operation: .delete)] = .alwaysAsk
        }
        return modes
    }

    static func permissionKey(area: AIPermissionArea, operation: AIPermissionOperation) -> String {
        "\(area.rawValue).\(operation.rawValue)"
    }
}

enum CheapestDefinition: String, Codable, CaseIterable {
    case absoluteCheapest = "Absolute Cheapest"
    case bestPracticalTrip = "Best Practical Trip"
    case oneStoreShop = "One-Store Shop"
    case preferredStoresOnly = "Preferred Stores Only"
    case custom = "Custom"
}
