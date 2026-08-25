import Foundation
import SwiftData

@Model
final class AppSnapshotRecord {
    @Attribute(.unique) var key: String
    var data: Data
    var updatedAt: Date

    init(key: String = "app-state", data: Data, updatedAt: Date = Date()) {
        self.key = key
        self.data = data
        self.updatedAt = updatedAt
    }
}

struct AppStoreSnapshot: Codable {
    var settings: AppSettings
    var chains: [SupermarketChain]
    var branches: [StoreBranch]
    var products: [Product]
    var priceObservations: [PriceObservation]
    var communityContributions: [CommunityContribution]
    var shoppingLists: [ShoppingList]
    var recipes: [Recipe]
    var mealPlans: [MealPlan]
    var matkasseBoxes: [MatkasseBox]
    var memories: [AIMemory]
    var household: Household?
    var invitations: [Invitation]
    var chatSessions: [ChatSessionSnapshot]
    var selectedChatSessionID: UUID?
    var onboardingAnswers: [OnboardingQuestionID: String]

    @MainActor
    init(store: AppStore) {
        settings = store.settings
        chains = store.chains
        branches = store.branches
        products = store.products
        priceObservations = store.priceObservations
        communityContributions = store.communityContributions
        shoppingLists = store.shoppingLists
        recipes = store.recipes
        mealPlans = store.mealPlans
        matkasseBoxes = store.matkasseBoxes
        memories = store.memories
        household = store.household
        invitations = store.invitations
        chatSessions = store.chatSessions.map(ChatSessionSnapshot.init(session:))
        selectedChatSessionID = store.selectedChatSessionID
        onboardingAnswers = store.onboardingAnswers
    }

    enum CodingKeys: String, CodingKey {
        case settings
        case chains
        case branches
        case products
        case priceObservations
        case communityContributions
        case shoppingLists
        case recipes
        case mealPlans
        case matkasseBoxes
        case memories
        case household
        case invitations
        case chatSessions
        case selectedChatSessionID
        case onboardingAnswers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        settings = try container.decode(AppSettings.self, forKey: .settings)
        chains = try container.decode([SupermarketChain].self, forKey: .chains)
        branches = try container.decode([StoreBranch].self, forKey: .branches)
        products = try container.decode([Product].self, forKey: .products)
        priceObservations = try container.decode([PriceObservation].self, forKey: .priceObservations)
        communityContributions = try container.decodeIfPresent([CommunityContribution].self, forKey: .communityContributions) ?? []
        shoppingLists = try container.decode([ShoppingList].self, forKey: .shoppingLists)
        recipes = try container.decode([Recipe].self, forKey: .recipes)
        mealPlans = try container.decodeIfPresent([MealPlan].self, forKey: .mealPlans) ?? []
        matkasseBoxes = try container.decodeIfPresent([MatkasseBox].self, forKey: .matkasseBoxes) ?? []
        memories = try container.decode([AIMemory].self, forKey: .memories)
        household = try container.decodeIfPresent(Household.self, forKey: .household)
        invitations = try container.decodeIfPresent([Invitation].self, forKey: .invitations) ?? []
        chatSessions = try container.decode([ChatSessionSnapshot].self, forKey: .chatSessions)
        selectedChatSessionID = try container.decodeIfPresent(UUID.self, forKey: .selectedChatSessionID)
        onboardingAnswers = try container.decodeIfPresent([OnboardingQuestionID: String].self, forKey: .onboardingAnswers) ?? [:]
    }
}

struct ChatSessionSnapshot: Codable {
    var id: UUID
    var title: String
    var purpose: String
    var createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessageSnapshot]

    @MainActor
    init(session: ChatSession) {
        id = session.id
        title = session.title
        purpose = session.purpose.rawValue
        createdAt = session.createdAt
        updatedAt = session.updatedAt
        messages = session.messages.compactMap(ChatMessageSnapshot.init(message:))
    }

    var chatSession: ChatSession {
        ChatSession(
            id: id,
            title: title,
            messages: messages.map(\.chatMessage),
            purpose: ChatSessionPurpose(rawValue: purpose) ?? .general,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct ActivityTagSnapshot: Codable {
    var id: UUID
    var actionType: String
    var summary: String
    var timestamp: Date
    var affectedRecordIDs: [UUID]

    init(tag: ActivityTag) {
        id = tag.id
        actionType = tag.actionType.rawValue
        summary = tag.summary
        timestamp = tag.timestamp
        affectedRecordIDs = tag.affectedRecordIDs
    }

    var activityTag: ActivityTag? {
        guard let resolvedActionType = ProposedActionType(rawValue: actionType) else { return nil }
        return ActivityTag(
            id: id,
            actionType: resolvedActionType,
            summary: summary,
            timestamp: timestamp,
            affectedRecordIDs: affectedRecordIDs
        )
    }
}

struct ChatMessageSnapshot: Codable {
    enum Content: Codable {
        case text(String)
        case error(String)
        case activityTags([ActivityTagSnapshot])
        case onboardingComplete
    }

    var id: UUID
    var role: String
    var content: Content
    var timestamp: Date

    @MainActor
    init?(message: ChatMessage) {
        id = message.id
        role = message.role.rawValue
        timestamp = message.timestamp

        switch message.content {
        case .text(let text):
            content = .text(text)
        case .error(let error):
            content = .error(error.localizedDescription)
        case .activityTags(let tags):
            content = .activityTags(tags.map(ActivityTagSnapshot.init(tag:)))
        case .onboardingComplete:
            content = .onboardingComplete
        case .proposedActions:
            return nil
        }
    }

    var chatMessage: ChatMessage {
        let resolvedRole = ChatMessageRole(rawValue: role) ?? .assistant
        let resolvedContent: ChatMessageContent
        switch content {
        case .text(let text):
            resolvedContent = .text(text)
        case .error(let message):
            resolvedContent = .error(.unknown(message))
        case .activityTags(let tags):
            resolvedContent = .activityTags(tags.compactMap(\.activityTag))
        case .onboardingComplete:
            resolvedContent = .onboardingComplete
        }
        return ChatMessage(id: id, role: resolvedRole, content: resolvedContent, timestamp: timestamp)
    }
}

@MainActor
final class SwiftDataPersistenceStore {
    private let container: ModelContainer
    private let context: ModelContext
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(container: ModelContainer) {
        self.container = container
        self.context = container.mainContext
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.sortedKeys]
    }

    func loadSnapshot() -> AppStoreSnapshot? {
        let descriptor = FetchDescriptor<AppSnapshotRecord>(
            predicate: #Predicate { $0.key == "app-state" }
        )
        guard let record = try? context.fetch(descriptor).first else { return nil }
        return try? decoder.decode(AppStoreSnapshot.self, from: record.data)
    }

    func saveSnapshot(_ snapshot: AppStoreSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        let descriptor = FetchDescriptor<AppSnapshotRecord>(
            predicate: #Predicate { $0.key == "app-state" }
        )
        if let record = try? context.fetch(descriptor).first {
            record.data = data
            record.updatedAt = Date()
        } else {
            context.insert(AppSnapshotRecord(data: data))
        }

        if context.hasChanges {
            try? context.save()
        }
    }
}
