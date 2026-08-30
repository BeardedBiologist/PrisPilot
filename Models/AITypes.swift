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
    var capabilities: AIProviderCapabilities { get }
}

extension AIService {
    var capabilities: AIProviderCapabilities {
        AIProviderCapabilities(provider: providerName)
    }
}

protocol OnboardingAIService {
    func sendOnboardingTurn(
        question: OnboardingQuestion,
        userAnswer: String,
        knownAnswers: [OnboardingQuestionID: String],
        context: AIContext
    ) async throws -> OnboardingAIResult
}

protocol ReceiptParsingAIService {
    func parseReceiptLines(rawLines: [String], knownProducts: [Product]) async throws -> ParsedReceipt
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
    var currentDateISO: String
    var timeZoneIdentifier: String
    var localeSummary: String
    var settingsSummary: [String]
    var shoppingListSummaries: [String]
    var productSummaries: [String]
    var recentPriceSummaries: [String]
    var recipeSummaries: [String]
    var mealPlanSummaries: [String]
    var matkasseSummaries: [String]
    var memorySummaries: [String]

    static var empty: AIContext {
        AIContext(
            relevantMemories: [],
            availableShoppingLists: [],
            enabledStoreBranches: [],
            userPreferences: "",
            currency: .nok,
            currentDateISO: "",
            timeZoneIdentifier: "",
            localeSummary: "",
            settingsSummary: [],
            shoppingListSummaries: [],
            productSummaries: [],
            recentPriceSummaries: [],
            recipeSummaries: [],
            mealPlanSummaries: [],
            matkasseSummaries: [],
            memorySummaries: []
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
    let trace: AITraceMetadata?
    let assumptions: [String]

    init(
        textContent: String?,
        proposedActions: [ProposedAction],
        memoryProposals: [MemoryProposal],
        error: AIServiceError?,
        trace: AITraceMetadata? = nil,
        assumptions: [String] = []
    ) {
        self.textContent = textContent
        self.proposedActions = proposedActions
        self.memoryProposals = memoryProposals
        self.error = error
        self.trace = trace
        self.assumptions = assumptions
    }
}

// MARK: - Provider Metadata

struct AIProviderCapabilities: Codable {
    let provider: String
    let supportsFunctionCalling: Bool
    let supportsJSONMode: Bool
    let supportsStreaming: Bool
    let reportsTokenUsage: Bool
    let compatibleFallbackModels: [String]

    init(
        provider: String,
        supportsFunctionCalling: Bool = false,
        supportsJSONMode: Bool = false,
        supportsStreaming: Bool = false,
        reportsTokenUsage: Bool = false,
        compatibleFallbackModels: [String] = []
    ) {
        self.provider = provider
        self.supportsFunctionCalling = supportsFunctionCalling
        self.supportsJSONMode = supportsJSONMode
        self.supportsStreaming = supportsStreaming
        self.reportsTokenUsage = reportsTokenUsage
        self.compatibleFallbackModels = compatibleFallbackModels
    }
}

struct AITraceMetadata: Codable {
    let provider: String
    let model: String
    let promptVersion: String
    let schemaVersion: String
    let responseFormat: String
    let latencyMilliseconds: Int
    let capabilities: AIProviderCapabilities
    let fallbackModelsTried: [String]
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

struct MemoryProposal: Identifiable, Codable {
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
