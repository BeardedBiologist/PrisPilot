import Foundation

// MARK: - AI Service Protocol

protocol AIService {
    func send(
        messages: [AIMessage],
        context: AIContext,
        availableTools: [AIToolDefinition]
    ) async throws -> AIResponse

    var isAvailable: Bool { get }
    var providerName: String { get }
}

protocol OnboardingAIService {
    func sendOnboardingTurn(
        question: OnboardingQuestion,
        userAnswer: String,
        knownAnswers: [OnboardingQuestionID: String],
        context: AIContext
    ) async throws -> OnboardingAIResult
}

// MARK: - AI Message

struct AIMessage: Codable {
    let role: AIMessageRole
    let content: String
    let timestamp: Date

    init(role: AIMessageRole, content: String) {
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

enum AIMessageRole: String, Codable {
    case user
    case assistant
    case system
}

// MARK: - AI Context

struct AIContext {
    var relevantMemories: [AIMemory]
    var availableShoppingLists: [String]
    var enabledStoreBranches: [String]
    var userPreferences: String
    var currency: Currency

    static var empty: AIContext {
        AIContext(
            relevantMemories: [],
            availableShoppingLists: [],
            enabledStoreBranches: [],
            userPreferences: "",
            currency: .nok
        )
    }
}

// MARK: - AI Tool Definition

struct AIToolDefinition {
    let name: String
    let description: String
}

// MARK: - AI Response

struct AIResponse {
    let textContent: String?
    let proposedActions: [ProposedAction]
    let memoryProposals: [MemoryProposal]
    let error: AIServiceError?
}

struct OnboardingAIResult {
    let assistantText: String
    let shouldAdvance: Bool
    let normalizedAnswer: String?
    let proposedActions: [ProposedAction]
    let memoryProposals: [MemoryProposal]

    static func followUp(_ text: String) -> OnboardingAIResult {
        OnboardingAIResult(
            assistantText: text,
            shouldAdvance: false,
            normalizedAnswer: nil,
            proposedActions: [],
            memoryProposals: []
        )
    }
}

// MARK: - Memory Proposal

struct MemoryProposal: Identifiable {
    let id: UUID
    let memory: AIMemory
    let reason: String

    init(id: UUID = UUID(), memory: AIMemory, reason: String) {
        self.id = id
        self.memory = memory
        self.reason = reason
    }
}

// MARK: - AI Service Errors

enum AIServiceError: Error, LocalizedError {
    case quotaExhausted
    case offline
    case invalidAPIKey
    case invalidResponse
    case permissionDenied
    case modelOverloaded
    case modelUnavailable(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .quotaExhausted:
            return "The free AI allowance is temporarily exhausted. Please try again later."
        case .offline:
            return "No internet connection. Manual features are still available."
        case .invalidAPIKey:
            return "AI API key is missing or invalid. Please check Settings."
        case .invalidResponse:
            return "The AI returned an unexpected response."
        case .permissionDenied:
            return "This action requires your approval."
        case .modelOverloaded:
            return "The AI model is temporarily busy after trying the available Gemini models. Please try again in a moment."
        case .modelUnavailable(let model):
            return "The configured AI model is no longer available: \(model). Please update the Gemini model setting."
        case .unknown(let msg):
            return msg
        }
    }
}
