import Foundation

struct ChatSession: Identifiable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var purpose: ChatSessionPurpose
    var pendingClarification: ChatPendingClarification?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        messages: [ChatMessage] = [],
        purpose: ChatSessionPurpose = .general,
        pendingClarification: ChatPendingClarification? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.purpose = purpose
        self.pendingClarification = pendingClarification
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

struct ChatPendingClarification: Codable, Equatable {
    let question: String
    let candidates: [String]
    let originalUserText: String?
    let createdAt: Date

    init(question: String, candidates: [String] = [], originalUserText: String? = nil, createdAt: Date = Date()) {
        self.question = question
        self.candidates = candidates
        self.originalUserText = originalUserText
        self.createdAt = createdAt
    }
}

struct ChatPendingProposal: Identifiable {
    let messageID: UUID
    let pendingActionCount: Int
    let failedActionCount: Int
    let firstSummary: String

    var id: UUID { messageID }
}

struct ChatQuickAction: Identifiable, Hashable {
    let id = UUID()
    let systemImage: String
    let title: String
    let prompt: String
}

enum ChatSessionPurpose: String {
    case general
    case aiOnboarding
}

struct ChatMessage: Identifiable {
    let id: UUID
    let role: ChatMessageRole
    var content: ChatMessageContent
    var assumptions: [String]
    var trace: AITraceMetadata?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        role: ChatMessageRole,
        content: ChatMessageContent,
        assumptions: [String] = [],
        trace: AITraceMetadata? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.assumptions = assumptions
        self.trace = trace
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
