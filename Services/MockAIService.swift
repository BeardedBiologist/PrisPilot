import Foundation
import Observation

@Observable
class MockAIService: AIService, OnboardingAIService {
    let providerName = "Mock AI (Development)"
    var isAvailable = true
    private(set) var requestCount = 0

    func send(
        messages: [AIMessage],
        context: AIContext,
        availableTools: [AIToolDefinition]
    ) async throws -> AIResponse {
        requestCount += 1
        try await Task.sleep(for: .seconds(1.2))

        guard let lastMessage = messages.last else {
            return AIResponse(
                textContent: "Hello! I'm your grocery assistant. How can I help?",
                proposedActions: [],
                memoryProposals: [],
                error: nil
            )
        }

        if let scopedResponse = AIScopePolicy.localRefusal(for: lastMessage.content) {
            return scopedResponse
        }

        return generateResponse(for: lastMessage.content.lowercased(), context: context)
    }

    func sendOnboardingTurn(
        question: OnboardingQuestion,
        userAnswer: String,
        knownAnswers: [OnboardingQuestionID: String],
        context: AIContext
    ) async throws -> OnboardingAIResult {
        requestCount += 1
        try await Task.sleep(for: .seconds(0.5))

        let lowercasedAnswer = userAnswer.lowercased()
        if lowercasedAnswer.contains("later") || lowercasedAnswer.contains("skip") || lowercasedAnswer.contains("come back") {
            return OnboardingAIResult(
                assistantText: "No problem. We can come back to \(question.title.lowercased()) later.",
                shouldAdvance: true,
                normalizedAnswer: "Skipped for now",
                proposedActions: [],
                memoryProposals: []
            )
        }

        var actions: [ProposedAction] = []
        var memories: [MemoryProposal] = []
        if question.id == .stores {
            for store in mockStores(from: userAnswer) {
                actions.append(ProposedAction(
                    type: .createStore,
                    summary: "Add store: \(store.chain) \(store.branch)",
                    payload: .createStore(chainName: store.chain, branchName: store.branch, address: nil, isEnabled: true)
                ))
            }
        } else if [.dietaryNeeds, .productPreferences, .frequentProducts, .householdSize].contains(question.id) {
            let memory = AIMemory(summary: userAnswer, category: .preference, strength: .preference)
            memories.append(MemoryProposal(memory: memory, reason: "Captured during onboarding."))
        }

        let reply = actions.isEmpty && memories.isEmpty
            ? "Got it. I saved that for setup."
            : "Got it. I updated setup with what you told me."
        return OnboardingAIResult(
            assistantText: reply,
            shouldAdvance: true,
            normalizedAnswer: userAnswer,
            proposedActions: actions,
            memoryProposals: memories
        )
    }

    private func mockStores(from answer: String) -> [(chain: String, branch: String)] {
        let knownChains = ["Rema 1000", "Meny", "Kiwi", "Coop Extra", "Spar"]
        return knownChains.compactMap { chain in
            guard answer.localizedCaseInsensitiveContains(chain) else { return nil }
            let branch = answer.localizedCaseInsensitiveContains("pindsle") ? "Pindsle" : "Local branch"
            return (chain, branch)
        }
    }

    private func generateResponse(for input: String, context: AIContext) -> AIResponse {
        if input.contains("paid") || (input.contains("kr") && (input.contains(" at ") || input.contains(" kiwi") || input.contains(" rema") || input.contains(" meny"))) {
            return priceAndListResponse(input: input)
        }
        if (input.contains("add") || input.contains("put")) && (input.contains("list") || input.contains("shop")) {
            return addToListResponse(input: input)
        }
        if input.contains("remember") || input.contains("what do you know") || input.contains("what have you") {
            return memoryQueryResponse(context: context)
        }
        if input.contains("taco") || input.contains("recipe") || input.contains("dinner") || input.contains("meal") {
            return recipeShoppingResponse(input: input)
        }
        if input.contains("forget") || input.contains("don't remember") {
            return forgetResponse(input: input)
        }
        return defaultResponse()
    }

    private func priceAndListResponse(input: String) -> AIResponse {
        let priceAction = ProposedAction(
            type: .createPriceObservation,
            summary: "Add price: Minced beef — kr 39.90 / 400 g at Kiwi Majorstuen",
            payload: .createPriceObservation(
                productName: "Minced beef",
                storeBranchName: "Kiwi Majorstuen",
                price: 39.90,
                quantity: 400,
                unit: .grams,
                isPromotion: false,
                date: Date()
            ),
            riskLevel: .low
        )

        let listAction = ProposedAction(
            type: .addShoppingListItem,
            summary: "Add 2 × Minced beef (400 g) to Taco Night",
            payload: .addShoppingListItem(
                listName: "Taco Night",
                productName: "Minced beef",
                quantity: "2 × 400 g",
                notes: nil
            ),
            riskLevel: .low
        )

        return AIResponse(
            textContent: nil,
            proposedActions: [priceAction, listAction],
            memoryProposals: [],
            error: nil
        )
    }

    private func addToListResponse(input: String) -> AIResponse {
        let product: String
        if input.contains("milk") { product = "Milk" }
        else if input.contains("bread") { product = "Bread" }
        else if input.contains("egg") { product = "Eggs" }
        else if input.contains("butter") { product = "Butter" }
        else { product = "Item" }

        let action = ProposedAction(
            type: .addShoppingListItem,
            summary: "Add \(product) to Weekly Shop",
            payload: .addShoppingListItem(
                listName: "Weekly Shop",
                productName: product,
                quantity: "1",
                notes: nil
            ),
            riskLevel: .low
        )

        var memoryProposals: [MemoryProposal] = []
        if input.contains("don't like") || input.contains("not q") || input.contains("avoid") || input.contains("prefer") {
            let summary = extractMemorySummary(from: input, product: product)
            let memory = AIMemory(summary: summary, category: .preference, strength: .preference)
            memoryProposals.append(MemoryProposal(memory: memory, reason: "You mentioned a preference I can remember for future shopping trips."))
        }

        return AIResponse(textContent: nil, proposedActions: [action], memoryProposals: memoryProposals, error: nil)
    }

    private func memoryQueryResponse(context: AIContext) -> AIResponse {
        guard !context.relevantMemories.isEmpty else {
            return AIResponse(
                textContent: "I don't have any memories saved yet. As we shop together, I'll remember your preferences — like favourite brands, allergies, and how many people you're cooking for.",
                proposedActions: [],
                memoryProposals: [],
                error: nil
            )
        }
        let list = context.relevantMemories.map { "• \($0.summary)" }.joined(separator: "\n")
        return AIResponse(
            textContent: "Here's what I remember about your preferences:\n\n\(list)",
            proposedActions: [],
            memoryProposals: [],
            error: nil
        )
    }

    private func recipeShoppingResponse(input: String) -> AIResponse {
        let tacoItems = [
            ("🥩", "Minced beef"),
            ("🌮", "Taco shells"),
            ("🍅", "Salsa"),
            ("🥛", "Sour cream"),
            ("🧀", "Cheddar cheese"),
            ("🥬", "Lettuce"),
            ("🍅", "Tomatoes"),
            ("🌶️", "Santa Maria seasoning")
        ]

        let actions = tacoItems.map { emoji, item in
            ProposedAction(
                type: .addShoppingListItem,
                summary: "Add \(emoji) \(item) to Taco Night",
                payload: .addShoppingListItem(
                    listName: "Taco Night",
                    productName: item,
                    quantity: "1",
                    notes: nil
                ),
                riskLevel: .low
            )
        }

        return AIResponse(
            textContent: "🌮 Taco Night for 4: 🥩 minced beef, 🌮 shells, 🍅 salsa, 🥛 sour cream, 🧀 cheddar, 🥬 lettuce, and 🍅 tomatoes. Based on the prices I know, Kiwi Majorstuen is cheapest for most of these.",
            proposedActions: actions,
            memoryProposals: [],
            error: nil
        )
    }

    private func forgetResponse(input: String) -> AIResponse {
        let action = ProposedAction(
            type: .deleteMemory,
            summary: "Remove saved preference from AI Memory",
            payload: .generic(description: "Delete memory"),
            riskLevel: .medium
        )
        return AIResponse(
            textContent: "I'll remove that preference from my memory.",
            proposedActions: [action],
            memoryProposals: [],
            error: nil
        )
    }

    private func defaultResponse() -> AIResponse {
        AIResponse(
            textContent: "I can help you track grocery prices, manage shopping lists, and plan meals. Try:\n\n• \"I paid kr 39.90 for 400 g minced beef at Kiwi\"\n• \"Add milk to my weekly list\"\n• \"Plan taco night for four people\"\n• \"What do you remember about me?\"",
            proposedActions: [],
            memoryProposals: [],
            error: nil
        )
    }

    private func extractMemorySummary(from input: String, product: String) -> String {
        if input.contains("q milk") || input.contains("q-milk") { return "Prefers not to buy Q milk" }
        if input.contains("peanut") { return "Avoid peanuts (possible allergy — confirm)" }
        if input.contains("organic") { return "Prefers organic \(product) when available" }
        if input.contains("tine") { return "Prefers Tine brand milk" }
        return "Preference noted for \(product)"
    }
}
