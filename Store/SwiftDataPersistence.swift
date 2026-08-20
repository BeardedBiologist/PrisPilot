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
    var shoppingLists: [ShoppingList]
    var recipes: [Recipe]
    var memories: [AIMemory]
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
        shoppingLists = store.shoppingLists
        recipes = store.recipes
        memories = store.memories
        chatSessions = store.chatSessions.map(ChatSessionSnapshot.init(session:))
        selectedChatSessionID = store.selectedChatSessionID
        onboardingAnswers = store.onboardingAnswers
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

struct ChatMessageSnapshot: Codable {
    enum Content: Codable {
        case text(String)
        case error(String)
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
        case .onboardingComplete:
            content = .onboardingComplete
        case .proposedActions, .activityTags:
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
