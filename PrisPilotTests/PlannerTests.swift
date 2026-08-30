import Foundation
import Testing
@testable import PrisPilot

@MainActor
struct PlannerTests {

    // MARK: - Helpers

    private func makePlanner() -> AIActionPlanner {
        AIActionPlanner(appStore: AppStore())
    }

    private func draftAction(type: ProposedActionType, payload: ProposedActionPayload, summary: String = "Test action") -> AIDraftAction {
        AIDraftAction(
            proposedAction: ProposedAction(type: type, summary: summary, payload: payload),
            source: "test"
        )
    }

    // MARK: - Simple Outcome Routing

    @Test func plannerAnswerDraftProducesAnswerTurn() {
        let planner = makePlanner()
        let draft = AIIntentDraft(outcome: .answer, assistantText: "Here is some information.")
        guard case .answer(let text) = planner.plan(draft: draft) else {
            Issue.record("Expected .answer turn")
            return
        }
        #expect(text == "Here is some information.")
    }

    @Test func plannerRefusalDraftProducesRefusalTurn() {
        let planner = makePlanner()
        let draft = AIIntentDraft(outcome: .refusal, assistantText: "I can only help with PrisPilot tasks.")
        guard case .refusal(let text) = planner.plan(draft: draft) else {
            Issue.record("Expected .refusal turn")
            return
        }
        #expect(text == "I can only help with PrisPilot tasks.")
    }

    @Test func plannerFailureDraftProducesFailureTurn() {
        let planner = makePlanner()
        let draft = AIIntentDraft(outcome: .failure, error: .invalidResponse)
        if case .failure = planner.plan(draft: draft) {
            // pass
        } else {
            Issue.record("Expected .failure turn")
        }
    }

    @Test func plannerClarificationDraftProducesClarificationTurn() {
        let planner = makePlanner()
        let req = AIClarificationRequest(question: "Which list do you mean?")
        let draft = AIIntentDraft(outcome: .clarification, clarification: req)
        guard case .clarification(let r) = planner.plan(draft: draft) else {
            Issue.record("Expected .clarification turn")
            return
        }
        #expect(r.question == "Which list do you mean?")
    }

    @Test func plannerErrorInDraftProducesFailureTurn() {
        let planner = makePlanner()
        let draft = AIIntentDraft(outcome: .answer, assistantText: nil, error: .offline)
        if case .failure = planner.plan(draft: draft) {
            // pass
        } else {
            Issue.record("Expected .failure turn when draft carries an error")
        }
    }

    // MARK: - Proposal Routing

    @Test func plannerProposalWithValidActionsProducesProposalTurn() {
        let planner = makePlanner()
        let action = draftAction(
            type: .addShoppingListItem,
            payload: .addShoppingListItem(listName: "Weekly Shop", productName: "Bread", quantity: "1", notes: nil),
            summary: "Add Bread to Weekly Shop"
        )
        let draft = AIIntentDraft(outcome: .proposal, assistantText: "Adding bread.", actions: [action])
        guard case .proposal(_, let actions, _) = planner.plan(draft: draft) else {
            Issue.record("Expected .proposal turn for valid proposed action")
            return
        }
        #expect(actions.count == 1)
        #expect(actions.first?.type == .addShoppingListItem)
    }

    @Test func plannerProposalActionCountMatchesDraftActions() {
        let planner = makePlanner()
        let actions = [
            draftAction(type: .addShoppingListItem, payload: .addShoppingListItem(listName: "Weekly Shop", productName: "Milk", quantity: "2", notes: nil), summary: "Add Milk"),
            draftAction(type: .addShoppingListItem, payload: .addShoppingListItem(listName: "Weekly Shop", productName: "Eggs", quantity: "12", notes: nil), summary: "Add Eggs")
        ]
        let draft = AIIntentDraft(outcome: .proposal, actions: actions)
        guard case .proposal(_, let result, _) = planner.plan(draft: draft) else {
            Issue.record("Expected .proposal with two actions")
            return
        }
        #expect(result.count == 2)
    }

    @Test func plannerProposalWithMemoryOnlyProducesProposalTurn() {
        let planner = makePlanner()
        let memory = AIMemory(summary: "Prefers oat milk", category: .preference)
        let proposal = MemoryProposal(memory: memory, reason: "User mentioned preference.")
        let draft = AIIntentDraft(outcome: .proposal, memoryProposals: [proposal])
        if case .proposal(_, _, let memoryProposals) = planner.plan(draft: draft) {
            #expect(memoryProposals.count == 1)
        } else {
            Issue.record("Expected .proposal turn when only memory proposals exist")
        }
    }

    @Test func plannerEmptyProposalWithTextFallsBackToAnswer() {
        let planner = makePlanner()
        let draft = AIIntentDraft(outcome: .proposal, assistantText: "Nothing to propose right now.", actions: [], memoryProposals: [])
        if case .answer(let text) = planner.plan(draft: draft) {
            #expect(text == "Nothing to propose right now.")
        } else {
            Issue.record("Expected .answer fallback for empty proposal with text")
        }
    }

    @Test func plannerEmptyProposalWithNoTextProducesFailure() {
        let planner = makePlanner()
        let draft = AIIntentDraft(outcome: .proposal, assistantText: nil, actions: [], memoryProposals: [])
        if case .failure = planner.plan(draft: draft) {
            // pass
        } else {
            Issue.record("Expected .failure when proposal has no actions, no memory, and no text")
        }
    }

    @Test func plannerProposalInvalidActionCarriesValidationResult() {
        let planner = makePlanner()
        let action = draftAction(
            type: .createPriceObservation,
            payload: .createPriceObservation(
                productName: "Milk",
                storeBranchName: "Kiwi Pindsle",
                price: 0,
                quantity: 1,
                unit: .litres,
                isPromotion: false,
                date: Date()
            ),
            summary: "Add price: Milk — kr 0"
        )
        let draft = AIIntentDraft(outcome: .proposal, actions: [action])
        guard case .proposal(_, let actions, _) = planner.plan(draft: draft) else {
            Issue.record("Expected .proposal even with invalid action (validation is informational)")
            return
        }
        let result = actions.first?.validationResult
        if case .invalid = result {
            // pass – price zero should be invalid
        } else {
            Issue.record("Expected .invalid validation on zero-price action")
        }
    }
}
