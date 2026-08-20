import Foundation

struct OnboardingQuestion: Identifiable, Hashable {
    let id: OnboardingQuestionID
    let title: String
    let prompt: String
    let detail: String
    let options: [String]
    let allowsFreeText: Bool

    init(
        id: OnboardingQuestionID,
        title: String,
        prompt: String,
        detail: String,
        options: [String] = [],
        allowsFreeText: Bool = true
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.detail = detail
        self.options = options
        self.allowsFreeText = allowsFreeText
    }
}

enum OnboardingQuestionID: String, CaseIterable, Codable, Hashable {
    case countryRegion
    case stores
    case cheapestDefinition
    case maxStoreCount
    case minimumSavings
    case aiPermissions
    case dietaryNeeds
    case productPreferences
    case frequentProducts
    case householdSize
}

enum OnboardingFlow {
    static let questions: [OnboardingQuestion] = [
        OnboardingQuestion(
            id: .countryRegion,
            title: "Country and region",
            prompt: "First, where should PrisPilot be set up? Norway and NOK are the default, but tell me your region or area too.",
            detail: "Country, region, currency, language, and measurement system."
        ),
        OnboardingQuestion(
            id: .stores,
            title: "Preferred stores",
            prompt: "Which supermarket chains or specific branches do you usually shop at?",
            detail: "Nearby or preferred supermarkets, enabled chains, and specific branches."
        ),
        OnboardingQuestion(
            id: .cheapestDefinition,
            title: "Cheapest means",
            prompt: "When I say cheapest, what should I optimize for?",
            detail: "Choose how PrisPilot balances low prices against convenience.",
            options: CheapestDefinition.allCases.map(\.rawValue),
            allowsFreeText: false
        ),
        OnboardingQuestion(
            id: .maxStoreCount,
            title: "Store limit",
            prompt: "What is the maximum number of stores you are willing to visit for one shopping trip?",
            detail: "This keeps shopping plans practical.",
            options: ["1", "2", "3", "No limit"]
        ),
        OnboardingQuestion(
            id: .minimumSavings,
            title: "Extra-store savings",
            prompt: "How much money should an extra store save before it is worth adding to a trip?",
            detail: "For example: kr 20, kr 50, or only for major savings.",
            options: ["kr 20", "kr 50", "kr 100"]
        ),
        OnboardingQuestion(
            id: .aiPermissions,
            title: "AI permissions",
            prompt: "How cautious should I be when proposing changes? The recommended setting is to ask before creating or editing anything.",
            detail: "AI access and confirmation permissions.",
            options: ["Ask before changes", "Allow low-risk changes", "Always ask"]
        ),
        OnboardingQuestion(
            id: .dietaryNeeds,
            title: "Diet and allergies",
            prompt: "Do you have allergies, dietary requirements, or ingredients that should never be substituted?",
            detail: "Sensitive requirements are kept separate from ordinary preferences."
        ),
        OnboardingQuestion(
            id: .productPreferences,
            title: "Product preferences",
            prompt: "Any favourite or disliked products, brands, package sizes, or substitutions I should remember?",
            detail: "Favourite brands, disliked brands, quality preferences, variants, and substitutions."
        ),
        OnboardingQuestion(
            id: .frequentProducts,
            title: "Frequent products",
            prompt: "What products do you buy regularly?",
            detail: "The catalogue can start from products you often buy."
        ),
        OnboardingQuestion(
            id: .householdSize,
            title: "Household and portions",
            prompt: "How many people do you usually shop or cook for, and what are typical meal portions?",
            detail: "Individual or household usage, household size, and meal portions."
        )
    ]

    static func question(after index: Int) -> OnboardingQuestion? {
        guard questions.indices.contains(index) else { return nil }
        return questions[index]
    }
}
