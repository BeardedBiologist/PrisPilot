import Foundation

@MainActor
struct AIActionPlanner {
    private let appStore: AppStore

    init(appStore: AppStore) {
        self.appStore = appStore
    }

    func plan(response: AIResponse) -> AIPlannedTurn {
        plan(draft: AIIntentDraft.fromLegacyResponse(response))
    }

    func plan(draft: AIIntentDraft) -> AIPlannedTurn {
        if let error = draft.error {
            return .failure(error)
        }

        switch draft.outcome {
        case .failure:
            return .failure(.invalidResponse)
        case .refusal:
            return .refusal(draft.assistantText ?? fallbackRefusal)
        case .answer:
            return .answer(draft.assistantText ?? fallbackAnswer)
        case .clarification:
            if let clarification = draft.clarification {
                return .clarification(clarification)
            }
            return .clarification(AIClarificationRequest(question: draft.assistantText ?? fallbackClarification))
        case .proposal:
            return planProposal(draft: draft)
        }
    }

    private func planProposal(draft: AIIntentDraft) -> AIPlannedTurn {
        let actions = draft.actions.map { draftAction in
            var action = draftAction.proposedAction
            action.validationResult = appStore.validate(action)
            return action
        }

        if let clarification = draft.clarification, draft.memoryProposals.isEmpty {
            return .clarification(clarification)
        }

        if let question = actions.compactMap(\.validationResult.clarificationQuestion).first,
           draft.memoryProposals.isEmpty {
            return .clarification(AIClarificationRequest(question: question))
        }

        if actions.isEmpty && draft.memoryProposals.isEmpty {
            if let text = draft.assistantText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .answer(text)
            }
            return .failure(.invalidResponse)
        }

        return .proposal(
            intro: draft.assistantText,
            actions: actions,
            memoryProposals: draft.memoryProposals
        )
    }

    private var fallbackAnswer: String {
        "I could not turn that into a clear PrisPilot action. Try naming the list, product, store, recipe, date, or setting you want me to change."
    }

    private var fallbackClarification: String {
        "Which PrisPilot item should I use?"
    }

    private var fallbackRefusal: String {
        "I can only help with PrisPilot grocery, shopping, price, recipe, meal planning, store, household, setting, and memory tasks."
    }
}
