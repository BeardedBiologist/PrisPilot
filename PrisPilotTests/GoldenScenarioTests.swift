import Foundation
import Testing
@testable import PrisPilot

// Golden scenario tests assert that scripted AI responses produce the expected
// planned turn type and action payloads without requiring a live API key.
// Each test builds an AIResponse as a real AI would produce it, runs it through
// AIActionPlanner.plan(response:), and asserts the outcome.

@MainActor
struct GoldenScenarioTests {

    // MARK: - Helpers

    private func planner() -> AIActionPlanner {
        AIActionPlanner(appStore: AppStore())
    }

    private func planner(store: AppStore) -> AIActionPlanner {
        AIActionPlanner(appStore: store)
    }

    private func priceAction(product: String, store storeBranch: String, price: Decimal, unit: MeasurementUnit = .litres) -> ProposedAction {
        ProposedAction(
            type: .createPriceObservation,
            summary: "Add price: \(product) — kr \(price) at \(storeBranch)",
            payload: .createPriceObservation(
                productName: product,
                storeBranchName: storeBranch,
                price: price,
                quantity: 1,
                unit: unit,
                isPromotion: false,
                date: Date()
            ),
            riskLevel: .low
        )
    }

    private func addItemAction(list: String, product: String, quantity: String = "1") -> ProposedAction {
        ProposedAction(
            type: .addShoppingListItem,
            summary: "Add \(product) to \(list)",
            payload: .addShoppingListItem(listName: list, productName: product, quantity: quantity, notes: nil),
            riskLevel: .low
        )
    }

    // MARK: - Price Logging Scenarios

    @Test func goldenPriceLogSingleProductSingleStore() {
        let response = AIResponse(
            textContent: nil,
            proposedActions: [priceAction(product: "Whole Milk", store: "Kiwi Pindsle", price: 24.90)],
            memoryProposals: [],
            error: nil
        )
        guard case .proposal(_, let actions, _) = planner().plan(response: response) else {
            Issue.record("Expected proposal for single price log")
            return
        }
        #expect(actions.count == 1)
        #expect(actions.first?.type == .createPriceObservation)
    }

    @Test func goldenPriceLogMultipleProductsAtSameStore() {
        let response = AIResponse(
            textContent: "I logged prices for your shop.",
            proposedActions: [
                priceAction(product: "Milk", store: "Rema 1000 Bjørvika", price: 22.90),
                priceAction(product: "Bread", store: "Rema 1000 Bjørvika", price: 39.90),
                priceAction(product: "Butter", store: "Rema 1000 Bjørvika", price: 49.00, unit: .grams)
            ],
            memoryProposals: [],
            error: nil
        )
        guard case .proposal(let intro, let actions, _) = planner().plan(response: response) else {
            Issue.record("Expected proposal for multiple price logs")
            return
        }
        #expect(actions.count == 3)
        #expect(actions.allSatisfy { $0.type == .createPriceObservation })
        #expect(intro == "I logged prices for your shop.")
    }

    @Test func goldenPriceLogWithIntroText() {
        let response = AIResponse(
            textContent: "Got it. Here's what I found.",
            proposedActions: [priceAction(product: "Eggs 12-pack", store: "Meny Aker Brygge", price: 59.90, unit: .packs)],
            memoryProposals: [],
            error: nil
        )
        guard case .proposal(let intro, _, _) = planner().plan(response: response) else {
            Issue.record("Expected proposal with intro text")
            return
        }
        #expect(intro == "Got it. Here's what I found.")
    }

    // MARK: - Shopping List Scenarios

    @Test func goldenAddSingleItemToList() {
        let response = AIResponse(
            textContent: nil,
            proposedActions: [addItemAction(list: "Weekly Shop", product: "Avocado")],
            memoryProposals: [],
            error: nil
        )
        guard case .proposal(_, let actions, _) = planner().plan(response: response) else {
            Issue.record("Expected proposal for add-to-list")
            return
        }
        #expect(actions.first?.type == .addShoppingListItem)
    }

    @Test func goldenAddMultipleItemsToList() {
        let items = ["Pasta", "Tomatoes", "Basil", "Parmesan"]
        let response = AIResponse(
            textContent: "Adding pasta ingredients.",
            proposedActions: items.map { addItemAction(list: "Weekly Shop", product: $0) },
            memoryProposals: [],
            error: nil
        )
        guard case .proposal(_, let actions, _) = planner().plan(response: response) else {
            Issue.record("Expected proposal for multiple items")
            return
        }
        #expect(actions.count == 4)
    }

    @Test func goldenRemoveItemFromList() {
        let response = AIResponse(
            textContent: nil,
            proposedActions: [ProposedAction(
                type: .removeShoppingListItem,
                summary: "Remove Milk from Weekly Shop",
                payload: .removeShoppingListItem(listName: "Weekly Shop", productName: "Milk"),
                riskLevel: .medium
            )],
            memoryProposals: [],
            error: nil
        )
        guard case .proposal(_, let actions, _) = planner().plan(response: response) else {
            Issue.record("Expected proposal for remove item")
            return
        }
        #expect(actions.first?.type == .removeShoppingListItem)
    }

    @Test func goldenMarkItemBought() {
        let response = AIResponse(
            textContent: nil,
            proposedActions: [ProposedAction(
                type: .completeShoppingListItem,
                summary: "Mark bought: Bread on Weekly Shop",
                payload: .completeShoppingListItem(listName: "Weekly Shop", productName: "Bread", isCompleted: true),
                riskLevel: .low
            )],
            memoryProposals: [],
            error: nil
        )
        guard case .proposal(_, let actions, _) = planner().plan(response: response) else {
            Issue.record("Expected proposal for mark-bought")
            return
        }
        #expect(actions.first?.type == .completeShoppingListItem)
    }

    @Test func goldenDeleteShoppingList() {
        let response = AIResponse(
            textContent: nil,
            proposedActions: [ProposedAction(
                type: .deleteShoppingList,
                summary: "Delete list: Weekly Shop",
                payload: .deleteShoppingList(listName: "Weekly Shop"),
                riskLevel: .high
            )],
            memoryProposals: [],
            error: nil
        )
        guard case .proposal(_, let actions, _) = planner().plan(response: response) else {
            Issue.record("Expected proposal for delete list")
            return
        }
        #expect(actions.first?.type == .deleteShoppingList)
        #expect(actions.first?.riskLevel == .high)
    }

    // MARK: - Memory Scenarios

    @Test func goldenMemoryProposalOnlyProducesProposal() {
        let memory = AIMemory(summary: "Prefers Tine brand milk", category: .preference)
        let proposal = MemoryProposal(memory: memory, reason: "You mentioned it in your message.")
        let response = AIResponse(
            textContent: "Noted! I'll remember that.",
            proposedActions: [],
            memoryProposals: [proposal],
            error: nil
        )
        guard case .proposal(_, _, let memoryProposals) = planner().plan(response: response) else {
            Issue.record("Expected proposal for memory-only response")
            return
        }
        #expect(memoryProposals.count == 1)
        #expect(memoryProposals.first?.memory.summary == "Prefers Tine brand milk")
    }

    @Test func goldenActionsAndMemoryTogetherProduceProposal() {
        let memory = AIMemory(summary: "Buys organic produce when possible", category: .preference)
        let proposal = MemoryProposal(memory: memory, reason: "User mentioned preference.")
        let response = AIResponse(
            textContent: nil,
            proposedActions: [addItemAction(list: "Weekly Shop", product: "Organic Carrots")],
            memoryProposals: [proposal],
            error: nil
        )
        guard case .proposal(_, let actions, let memoryProposals) = planner().plan(response: response) else {
            Issue.record("Expected proposal combining actions and memory")
            return
        }
        #expect(actions.count == 1)
        #expect(memoryProposals.count == 1)
    }

    // MARK: - Text Answer Scenarios

    @Test func goldenTextOnlyResponseProducesAnswer() {
        let response = AIResponse(
            textContent: "I can help you track grocery prices and plan shopping.",
            proposedActions: [],
            memoryProposals: [],
            error: nil
        )
        guard case .answer(let text) = planner().plan(response: response) else {
            Issue.record("Expected .answer for text-only response")
            return
        }
        #expect(!text.isEmpty)
    }

    @Test func goldenMemoryQueryAnswerContainsText() {
        let response = AIResponse(
            textContent: "Here's what I remember: • Family of 4 • Prefers Tine milk",
            proposedActions: [],
            memoryProposals: [],
            error: nil
        )
        if case .answer(let text) = planner().plan(response: response) {
            #expect(text.contains("remember"))
        } else {
            Issue.record("Expected .answer for memory query")
        }
    }

    // MARK: - Error Scenarios

    @Test func goldenServiceErrorProducesFailureTurn() {
        let response = AIResponse(
            textContent: nil,
            proposedActions: [],
            memoryProposals: [],
            error: .offline
        )
        if case .failure = planner().plan(response: response) {
            // pass
        } else {
            Issue.record("Expected .failure turn for service error")
        }
    }

    @Test func goldenQuotaExhaustedProducesFailureTurn() {
        let response = AIResponse(
            textContent: nil,
            proposedActions: [],
            memoryProposals: [],
            error: .quotaExhausted
        )
        if case .failure = planner().plan(response: response) {
            // pass
        } else {
            Issue.record("Expected .failure turn for quota exhausted error")
        }
    }

    // MARK: - Scope Policy Scenarios

    @Test func goldenScopePolicyBlocksCodingRequest() {
        let result = AIScopePolicy.localRefusal(for: "Can you write a Swift function for me?")
        #expect(result != nil)
        if let text = result?.textContent {
            #expect(!text.isEmpty)
        }
    }

    @Test func goldenScopePolicyBlocksMathHomework() {
        let result = AIScopePolicy.localRefusal(for: "Help me solve this calculus problem")
        #expect(result != nil)
    }

    @Test func goldenScopePolicyAllowsPriceLogging() {
        let result = AIScopePolicy.localRefusal(for: "I paid kr 45 for milk at Kiwi today")
        #expect(result == nil)
    }

    @Test func goldenScopePolicyAllowsShoppingListRequest() {
        let result = AIScopePolicy.localRefusal(for: "Add bread and eggs to my list")
        #expect(result == nil)
    }

    @Test func goldenScopePolicyAllowsRecipePlanning() {
        let result = AIScopePolicy.localRefusal(for: "Plan a taco night for 4 people under kr 300")
        #expect(result == nil)
    }
}
