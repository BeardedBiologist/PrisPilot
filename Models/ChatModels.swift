import Foundation

struct ChatSession: Identifiable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var purpose: ChatSessionPurpose
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        messages: [ChatMessage] = [],
        purpose: ChatSessionPurpose = .general,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.purpose = purpose
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var previewText: String {
        for message in messages.reversed() {
            if case .text(let text) = message.content {
                return text
            }
        }
        return "No messages yet"
    }
}

enum ChatSessionPurpose: String {
    case general
    case aiOnboarding
}

struct ChatMessage: Identifiable {
    let id: UUID
    let role: ChatMessageRole
    var content: ChatMessageContent
    let timestamp: Date

    init(id: UUID = UUID(), role: ChatMessageRole, content: ChatMessageContent, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

enum ChatMessageRole: String {
    case user
    case assistant
}

enum ChatMessageContent {
    case text(String)
    case proposedActions(intro: String?, actions: [ProposedAction], memoryProposals: [MemoryProposal])
    case activityTags([ActivityTag])
    case error(AIServiceError)
    case onboardingComplete
}
