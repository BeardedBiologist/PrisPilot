import Foundation

// MARK: - Draft Intent Models

enum AITurnOutcome: String {
    case answer
    case clarification
    case proposal
    case refusal
    case failure
}

struct AIClarificationRequest: Identifiable {
    let id: UUID
    let question: String
    let candidates: [String]

    init(id: UUID = UUID(), question: String, candidates: [String] = []) {
        self.id = id
        self.question = question
        self.candidates = candidates
    }
}

struct AIDraftAction: Identifiable {
    let id: UUID
    var proposedAction: ProposedAction
    var source: String

    init(id: UUID = UUID(), proposedAction: ProposedAction, source: String) {
        self.id = id
        self.proposedAction = proposedAction
        self.source = source
    }
}

struct AIIntentDraft {
    static let schemaVersion = "2026-08-30.phase9.legacy-function-draft-v1"

    var outcome: AITurnOutcome
    var assistantText: String?
    var clarification: AIClarificationRequest?
    var assumptions: [String]
    var actions: [AIDraftAction]
    var memoryProposals: [MemoryProposal]
    var error: AIServiceError?

    init(
        outcome: AITurnOutcome,
        assistantText: String? = nil,
        clarification: AIClarificationRequest? = nil,
        assumptions: [String] = [],
        actions: [AIDraftAction] = [],
        memoryProposals: [MemoryProposal] = [],
        error: AIServiceError? = nil
    ) {
        self.outcome = outcome
        self.assistantText = assistantText
        self.clarification = clarification
        self.assumptions = assumptions
        self.actions = actions
        self.memoryProposals = memoryProposals
        self.error = error
    }

    static func fromLegacyResponse(_ response: AIResponse, source: String = "legacyResponse") -> AIIntentDraft {
        if let error = response.error {
            return AIIntentDraft(outcome: .failure, error: error)
        }

        let draftActions = response.proposedActions.map { action in
            AIDraftAction(proposedAction: action, source: source)
        }

        if !draftActions.isEmpty || !response.memoryProposals.isEmpty {
            return AIIntentDraft(
                outcome: .proposal,
                assistantText: response.textContent,
                assumptions: response.assumptions,
                actions: draftActions,
                memoryProposals: response.memoryProposals
            )
        }

        if let text = response.textContent {
            return AIIntentDraft(outcome: .answer, assistantText: text)
        }

        return AIIntentDraft(outcome: .failure, error: .invalidResponse)
    }

    func legacyResponse() -> AIResponse {
        AIResponse(
            textContent: clarification?.question ?? assistantText,
            proposedActions: actions.map(\.proposedAction),
            memoryProposals: memoryProposals,
            error: error,
            assumptions: assumptions
        )
    }
}

enum AIPlannedTurn {
    case answer(String)
    case clarification(AIClarificationRequest)
    case proposal(intro: String?, actions: [ProposedAction], memoryProposals: [MemoryProposal])
    case refusal(String)
    case failure(AIServiceError)
}
