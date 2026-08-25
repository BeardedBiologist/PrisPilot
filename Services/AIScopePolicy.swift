import Foundation

enum AIScopePolicy {
    static func localRefusal(for input: String) -> AIResponse? {
        guard isClearlyOutOfScope(input) else { return nil }
        return AIResponse(
            textContent: refusalText,
            proposedActions: [],
            memoryProposals: [],
            error: nil
        )
    }

    private static let refusalText = "I can only help with PrisPilot tasks: grocery prices, shopping lists, budgets, recipes, meal planning, stores, household shopping, app settings, and shopping preferences. Try asking me to compare prices, plan a meal, build a list, or track what you paid."

    private static func isClearlyOutOfScope(_ input: String) -> Bool {
        let text = input.lowercased()
        let normalized = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let tokenSet = Set(normalized)

        if containsAny(scopePhrases, in: text) || !tokenSet.isDisjoint(with: scopeTerms) {
            return false
        }

        if containsAny(blockedPhrases, in: text) || !tokenSet.isDisjoint(with: blockedTerms) {
            return true
        }

        let looksLikeGeneralQuestion = text.contains("?") || text.hasPrefix("what ") || text.hasPrefix("why ") || text.hasPrefix("how ") || text.hasPrefix("explain ")
        return looksLikeGeneralQuestion
    }

    private static func containsAny(_ phrases: [String], in text: String) -> Bool {
        phrases.contains { text.contains($0) }
    }

    private static let scopePhrases = [
        "shopping list", "grocery list", "meal plan", "plan dinner", "plan meals",
        "grocery budget", "food budget", "weekly shop", "price comparison", "compare prices",
        "cheapest shop", "cheapest store", "supermarket", "rema 1000", "coop extra"
    ]

    private static let scopeTerms: Set<String> = [
        "grocery", "groceries", "shopping", "shop", "list", "lists", "price", "prices", "paid",
        "cost", "costs", "cheap", "cheapest", "budget", "budgets", "saving", "savings",
        "recipe", "recipes", "meal", "meals", "dinner", "lunch", "breakfast", "ingredient", "ingredients",
        "store", "stores", "supermarket", "branch", "branches", "kiwi", "rema", "meny", "coop", "spar",
        "nok", "kr", "kg", "g", "gram", "grams", "liter", "litre", "liters", "litres", "ml", "pack", "packs",
        "milk", "bread", "eggs", "egg", "butter", "cheese", "beef", "chicken", "fish", "salmon", "pork",
        "tomato", "tomatoes", "potato", "potatoes", "onion", "onions", "carrot", "carrots", "lettuce",
        "rice", "pasta", "taco", "tacos", "salsa", "cream", "yogurt", "apple", "apples", "banana", "bananas",
        "preference", "preferences", "remember", "forget", "memory", "allergy", "allergies", "diet", "dietary",
        "household", "currency", "settings", "onboarding"
    ]

    private static let blockedPhrases = [
        "write code", "write a function", "debug this", "code review", "leetcode", "unit test",
        "solve this puzzle", "logic puzzle", "write an essay", "write a poem", "tell me a joke",
        "translate this", "summarize this", "stock market", "investment advice", "legal advice"
    ]

    private static let blockedTerms: Set<String> = [
        "code", "coding", "program", "programming", "python", "javascript", "typescript", "swift", "xcode",
        "html", "css", "sql", "regex", "algorithm", "homework", "essay", "poem", "joke", "riddle",
        "history", "politics", "weather", "news", "celebrity", "movie", "movies", "game", "games",
        "stocks", "crypto", "bitcoin", "investment", "lawyer", "lawsuit"
    ]
}
