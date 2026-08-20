import Foundation

struct ChatSession: Identifiable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
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

enum ChatMessageRole {
    case user
    case assistant
}

enum ChatMessageContent {
    case text(String)
    case proposedActions(intro: String?, actions: [ProposedAction], memoryProposals: [MemoryProposal])
    case activityTags([ActivityTag])
    case error(AIServiceError)
}
