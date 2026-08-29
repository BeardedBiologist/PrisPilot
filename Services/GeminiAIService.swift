import Foundation

// Gemini Developer API via REST — no SDK dependency needed.
// Key is read from Keychain; never embedded in source.

final class GeminiAIService: AIService, OnboardingAIService, ReceiptParsingAIService {
    let providerName: String
    var isAvailable: Bool = true

    private let apiKey: String
    private let model: String
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    private let fallbackModels = ["gemini-2.5-flash-lite", "gemini-3.5-flash", "gemini-3.5-flash-lite", "gemini-3.1-flash-lite"]
    private let requestAttemptCount = 2
    private let retryDelay: Duration = .milliseconds(700)

    init(apiKey: String, model: String = "gemini-2.5-flash") {
        self.apiKey = apiKey
        self.model = model
        self.providerName = "Gemini (\(model))"
    }

    // MARK: - AIService

    func send(
        messages: [AIMessage],
        context: AIContext,
        availableTools: [AIToolDefinition]
    ) async throws -> AIResponse {
        let body = try buildRequestBody(messages: messages, context: context)
        let response = try await generateContentWithFallback(body: body)
        return parseResponse(response)
    }

    private func generateContentWithFallback(body: Data) async throws -> GeminiResponse {
        var lastRecoverableError: AIServiceError?

        for modelName in orderedModels {
            for attempt in 1...requestAttemptCount {
                do {
                    return try await generateContent(modelName: modelName, body: body)
                } catch let error as AIServiceError {
                    switch error {
                    case .modelOverloaded, .modelUnavailable:
                        lastRecoverableError = error
                        logRecoverableModelFailure(error, modelName: modelName, attempt: attempt)
                        if attempt < requestAttemptCount {
                            try? await Task.sleep(for: retryDelay)
                            continue
                        }
                    case .quotaExhausted, .invalidAPIKey, .offline, .invalidResponse, .permissionDenied, .unknown:
                        throw error
                    }
                }

                break
            }
        }

        throw lastRecoverableError ?? AIServiceError.modelOverloaded
    }

    private var orderedModels: [String] {
        var models = [model]
        for fallback in fallbackModels where !models.contains(fallback) {
            models.append(fallback)
        }
        return models
    }

    private func logRecoverableModelFailure(_ error: AIServiceError, modelName: String, attempt: Int) {
        #if DEBUG
        print("Gemini recoverable failure: model=\(modelName), attempt=\(attempt), error=\(error.localizedDescription)")
        #endif
    }

    private func generateContent(modelName: String, body: Data) async throws -> GeminiResponse {
        let url = URL(string: "\(baseURL)/\(modelName):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200:
                break
            case 401, 403:
                throw AIServiceError.invalidAPIKey
            case 429:
                throw AIServiceError.quotaExhausted
            default:
                throw parseHTTPError(statusCode: http.statusCode, data: data)
            }
        }

        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
        if let error = geminiResponse.error {
            if error.status == "RESOURCE_EXHAUSTED" { throw AIServiceError.quotaExhausted }
            if error.status == "UNAUTHENTICATED" { throw AIServiceError.invalidAPIKey }
            if error.status == "UNAVAILABLE" || error.message.localizedCaseInsensitiveContains("high demand") { throw AIServiceError.modelOverloaded }
            throw AIServiceError.unknown(error.message)
        }
        return geminiResponse
    }

    private func parseHTTPError(statusCode: Int, data: Data) -> AIServiceError {
        if let response = try? JSONDecoder().decode(GeminiResponse.self, from: data),
           let error = response.error {
            if error.status == "NOT_FOUND", error.message.contains("models/") {
                let modelName = error.message
                    .components(separatedBy: "models/")
                    .dropFirst()
                    .first?
                    .components(separatedBy: " ")
                    .first ?? model
                return .modelUnavailable(modelName)
            }
            if error.status == "UNAVAILABLE" || error.message.localizedCaseInsensitiveContains("high demand") {
                return .modelOverloaded
            }
            return .unknown(error.message)
        }

        let body = String(data: data, encoding: .utf8) ?? "No response body"
        return .unknown("HTTP \(statusCode): \(body.prefix(200))")
    }

    // MARK: - Onboarding

    func sendOnboardingTurn(
        question: OnboardingQuestion,
        userAnswer: String,
        knownAnswers: [OnboardingQuestionID: String],
        context: AIContext
    ) async throws -> OnboardingAIResult {
        let body = try buildOnboardingRequestBody(question: question, userAnswer: userAnswer, knownAnswers: knownAnswers, context: context)
        let geminiResponse = try await generateContentWithFallback(body: body)

        guard let text = geminiResponse.candidates?.first?.content?.parts.compactMap(\.text).joined(),
              let jsonData = text.data(using: .utf8) else {
            throw AIServiceError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(GeminiOnboardingTurn.self, from: jsonData)
        return decoded.result(defaultAnswer: userAnswer)
    }

    private func buildOnboardingRequestBody(
        question: OnboardingQuestion,
        userAnswer: String,
        knownAnswers: [OnboardingQuestionID: String],
        context: AIContext
    ) throws -> Data {
        let known = knownAnswers.map { "\($0.key.rawValue): \($0.value)" }.sorted().joined(separator: "\n")
        let stores = context.enabledStoreBranches.joined(separator: ", ")
        let prompt = """
        You are PrisPilot's onboarding assistant. Be conversational and useful, but return only valid JSON.

        Current setup question:
        id: \(question.id.rawValue)
        title: \(question.title)
        prompt: \(question.prompt)
        detail: \(question.detail)
        options: \(question.options.joined(separator: ", "))

        User answer:
        \(userAnswer)

        Known onboarding answers:
        \(known.isEmpty ? "None" : known)

        Current saved store branches:
        \(stores.isEmpty ? "None" : stores)

        Decide whether the answer is enough to advance, whether to ask one concise follow-up, or whether the user wants to skip/come back later. If they say anything like "later", "skip", or "come back to that", advance with skipped=true.

        Extract structured effects when possible:
        - For stores, create one store object per physical branch mentioned.
        - For cheapestDefinition, use exactly one of: \(CheapestDefinition.allCases.map(\.rawValue).joined(separator: ", ")).
        - For maxStoreCount, extract an integer if present.
        - For minimumSavings, extract a NOK number if present.
        - For diet, preferences, frequent products, and household size, create memory summaries when useful.
        - For frequent products, create product names when useful.

        Return JSON matching this schema:
        {
          "assistantText": "short friendly response",
          "decision": "advance" | "followUp" | "skip",
          "normalizedAnswer": "clean answer or null",
          "settings": { "cheapestDefinition": null, "maxStoreCount": null, "minimumSavings": null },
          "stores": [{ "chainName": "Rema 1000", "branchName": "Pindsle", "address": null, "isEnabled": true }],
          "memories": [{ "summary": "Prefers Rema 1000", "category": "Preference", "strength": "Preference", "sensitivityLevel": "Standard" }],
          "products": [{ "name": "Milk", "category": "Dairy", "unit": "l" }]
        }
        """

        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": 2048,
                "responseMimeType": "application/json"
            ]
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Receipt Parsing

    func parseReceiptLines(rawLines: [String], knownProducts: [Product]) async throws -> ParsedReceipt {
        let body = try buildReceiptParsingRequestBody(rawLines: rawLines, knownProducts: knownProducts)
        let geminiResponse = try await generateContentWithFallback(body: body)

        guard let text = geminiResponse.candidates?.first?.content?.parts.compactMap(\.text).joined(),
              let jsonData = text.data(using: .utf8) else {
            throw AIServiceError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(GeminiReceiptParse.self, from: jsonData)
        return decoded.parsedReceipt(knownProducts: knownProducts)
    }

    private func buildReceiptParsingRequestBody(rawLines: [String], knownProducts: [Product]) throws -> Data {
        let productNames = knownProducts
            .map(\.name)
            .sorted()
            .prefix(80)
            .joined(separator: ", ")

        let prompt = """
        You are parsing OCR text from a Norwegian grocery receipt. Return only valid JSON.

        OCR lines:
        \(rawLines.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))

        Known product names in the app:
        \(productNames.isEmpty ? "None" : productNames)

        Extract grocery line items only. Ignore totals, payment lines, tax/MVA, receipt metadata, phone numbers, and organisation numbers.
        Prefer a known product name when it clearly matches an OCR item. Keep the original OCR line in rawText.
        Prices are NOK decimal numbers. Use null for productName or price if a line cannot be confidently parsed.
        Infer the supermarket chain or branch from receipt header text when possible.

        Return JSON matching this schema:
        {
          "inferredStoreName": "Kiwi" | "Rema 1000" | "Meny" | null,
          "lines": [
            { "rawText": "MELK 1L 22,90", "productName": "Milk", "price": 22.90, "include": true }
          ]
        }
        """

        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": [
                "temperature": 0.1,
                "maxOutputTokens": 4096,
                "responseMimeType": "application/json"
            ]
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Request Building

    private func buildRequestBody(messages: [AIMessage], context: AIContext) throws -> Data {
        let body: [String: Any] = [
            "contents": buildContents(from: messages),
            "systemInstruction": ["parts": [["text": buildSystemPrompt(context: context)]]],
            "tools": [["functionDeclarations": functionDeclarations()]],
            "generationConfig": ["temperature": 0.3, "maxOutputTokens": 2048]
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    private func buildContents(from messages: [AIMessage]) -> [[String: Any]] {
        messages.suffix(20).map { msg in
            [
                "role": msg.role == .user ? "user" : "model",
                "parts": [["text": msg.content]]
            ]
        }
    }

    private func buildSystemPrompt(context: AIContext) -> String {
        var lines = [
            "You are PrisPilot, an AI grocery shopping assistant for Norway.",
            "Help users track grocery prices, manage shopping lists, plan meals, and find the cheapest options.",
            "Currency: Norwegian Krone (NOK, symbol: kr). Understand Norwegian store and product names.",
            "",
            "SCOPE: Only answer requests that directly support PrisPilot's product areas: grocery prices, shopping lists, recipes, meal planning, grocery budgets, supermarket selection, household shopping, app settings, shopping preferences, and app memory.",
            "Refuse requests outside that scope, including coding, debugging, general reasoning puzzles, homework, trivia, news, entertainment, essays, translation, or other general assistant tasks. Do not answer the out-of-scope request; briefly redirect to what PrisPilot can do.",
            "If part of a request is in scope and part is out of scope, handle only the in-scope grocery/app part.",
            "",
            "STYLE: For recipe and shopping-list text, use relevant food emojis sparingly so items are easy to scan, e.g. 🍅 Tomatoes or 🥛 Milk. Keep emojis out of structured tool arguments such as productName, listName, storeBranchName, settings, and memory summaries.",
            "",
            "CRITICAL: Never perform actions directly. Use tools to PROPOSE changes. The user approves all proposals before execution.",
            "- Group related actions in one response (e.g. record a price AND add to list if user implies both).",
            "- Propose memory separately from shopping actions.",
            "- Keep text responses concise; let the proposed actions do the heavy lifting.",
            "- For prices, include quantity and unit when mentioned.",
            "- Stores are user-managed. If the user asks to add, edit, delete, enable, or disable supermarket branches, propose store actions. Do not assume Oslo branches."
        ]

        if !context.relevantMemories.isEmpty {
            lines += ["", "User preferences and memories:"]
            lines += context.relevantMemories.map { "- \($0.summary)" }
        }
        if !context.availableShoppingLists.isEmpty {
            lines.append("Available shopping lists: \(context.availableShoppingLists.joined(separator: ", "))")
        }
        if !context.enabledStoreBranches.isEmpty {
            lines.append("Known store branches: \(context.enabledStoreBranches.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }

    private func functionDeclarations() -> [[String: Any]] {
        [
            makeFn(
                name: "createPriceObservation",
                desc: "Record a price the user saw or paid for a product at a specific store. Use whenever the user mentions a price.",
                props: [
                    "productName":     strProp("Product name"),
                    "storeBranchName": strProp("Store and branch (e.g. 'Kiwi Majorstuen')"),
                    "price":           numProp("Price in NOK"),
                    "quantity":        numProp("Package quantity number (e.g. 400 for 400 g)"),
                    "unit":            enumProp("Unit of measurement", ["g", "kg", "ml", "l", "stk", "pk"]),
                    "isPromotion":     boolProp("True if this is a promotional or offer price")
                ],
                required: ["productName", "storeBranchName", "price"]
            ),
            makeFn(
                name: "addShoppingListItem",
                desc: "Add an item to a shopping list. Default list name is 'Weekly Shop' if unspecified.",
                props: [
                    "listName":    strProp("Shopping list name"),
                    "productName": strProp("Product to add"),
                    "quantity":    strProp("Quantity as natural text, e.g. '2', '400 g', '2 packs'"),
                    "notes":       strProp("Optional notes")
                ],
                required: ["listName", "productName", "quantity"]
            ),
            makeFn(
                name: "createShoppingList",
                desc: "Create a new named shopping list.",
                props: ["name": strProp("List name")],
                required: ["name"]
            ),
            makeFn(
                name: "updateShoppingList",
                desc: "Rename an existing shopping list, or set/change its planned shopping date.",
                props: [
                    "existingListName": strProp("Existing list name to update"),
                    "newName":          strProp("New name for the list, if renaming"),
                    "plannedDate":      strProp("New planned date in YYYY-MM-DD format, if setting/changing it")
                ],
                required: ["existingListName"]
            ),
            makeFn(
                name: "deleteShoppingList",
                desc: "Delete an entire shopping list. Only use when the user clearly asks to delete or remove a list.",
                props: ["listName": strProp("List name to delete")],
                required: ["listName"]
            ),
            makeFn(
                name: "updateShoppingListItem",
                desc: "Change the quantity or notes for an item already on a shopping list.",
                props: [
                    "listName":    strProp("Shopping list name"),
                    "productName": strProp("Existing item's product name"),
                    "newQuantity": strProp("New quantity as natural text, e.g. '2', '400 g'"),
                    "newNotes":    strProp("New notes")
                ],
                required: ["listName", "productName"]
            ),
            makeFn(
                name: "completeShoppingListItem",
                desc: "Mark a shopping list item as bought, or mark a previously-bought item as not bought again.",
                props: [
                    "listName":    strProp("Shopping list name"),
                    "productName": strProp("Item's product name"),
                    "isCompleted": boolProp("True to mark bought, false to mark not bought. Defaults to true.")
                ],
                required: ["listName", "productName"]
            ),
            makeFn(
                name: "removeShoppingListItem",
                desc: "Remove an item from a shopping list entirely, not just mark it bought.",
                props: [
                    "listName":    strProp("Shopping list name"),
                    "productName": strProp("Item's product name to remove")
                ],
                required: ["listName", "productName"]
            ),
            makeFn(
                name: "setShoppingListStatus",
                desc: "Change a shopping list's status — start shopping a planned list, mark it completed, or archive it.",
                props: [
                    "listName": strProp("Shopping list name"),
                    "status":   enumProp("New status", ["active", "completed", "archived"])
                ],
                required: ["listName", "status"]
            ),
            makeFn(
                name: "optimizeShoppingList",
                desc: "Re-run store/price optimization for a shopping list, assigning items to the cheapest practical stores.",
                props: ["listName": strProp("Shopping list name")],
                required: ["listName"]
            ),
            makeFn(
                name: "moveShoppingListItem",
                desc: "Manually reassign a shopping list item to a specific store, overriding the optimizer.",
                props: [
                    "listName":        strProp("Shopping list name"),
                    "productName":     strProp("Item's product name"),
                    "storeBranchName": strProp("Store to move the item to, e.g. 'Kiwi Majorstuen'")
                ],
                required: ["listName", "productName", "storeBranchName"]
            ),
            makeFn(
                name: "substituteShoppingListItem",
                desc: "Replace a shopping list item's product with a substitute — clears its price/store assignment since the substitute needs its own pricing.",
                props: [
                    "listName":       strProp("Shopping list name"),
                    "productName":    strProp("Existing item's product name"),
                    "newProductName": strProp("Substitute product name")
                ],
                required: ["listName", "productName", "newProductName"]
            ),
            makeFn(
                name: "addRecipeToShoppingList",
                desc: "Add all ingredients from a saved recipe to a shopping list.",
                props: [
                    "recipeName": strProp("Existing saved recipe's title"),
                    "listName":   strProp("Shopping list name to add ingredients to. Default 'Weekly Shop' if unspecified.")
                ],
                required: ["recipeName", "listName"]
            ),
            makeFn(
                name: "updateRecipe",
                desc: "Edit an existing recipe's title, description, or servings.",
                props: [
                    "existingTitle": strProp("Existing recipe title"),
                    "newTitle":      strProp("New title, if renaming"),
                    "description":   strProp("New description, if changing it"),
                    "servings":      numProp("New servings count, if changing it")
                ],
                required: ["existingTitle"]
            ),
            makeFn(
                name: "deleteRecipe",
                desc: "Delete a saved recipe. Only use when the user clearly asks to remove it.",
                props: ["title": strProp("Recipe title to delete")],
                required: ["title"]
            ),
            makeFn(
                name: "setMealPlanSlot",
                desc: "Plan a meal for a specific date and meal type — a saved recipe, a freeform meal that isn't a full recipe, or eating out. Overwrites whatever was already planned for that date+mealType.",
                props: [
                    "date":         strProp("Date in YYYY-MM-DD format"),
                    "mealType":     enumProp("Meal type", ["Breakfast", "Lunch", "Dinner"]),
                    "recipeTitle":  strProp("Existing saved recipe's title, if planning a recipe"),
                    "freeformText": strProp("Freeform meal description, if not a saved recipe (or a note for eating out)"),
                    "isEatingOut":  boolProp("True if this is an eating-out/takeaway meal rather than something cooked"),
                    "isLeftover":   boolProp("True if this reuses a previous meal's cooking rather than a new dish")
                ],
                required: ["date", "mealType"]
            ),
            makeFn(
                name: "removeMealPlanSlot",
                desc: "Clear a planned meal for a specific date and meal type.",
                props: [
                    "date":     strProp("Date in YYYY-MM-DD format"),
                    "mealType": enumProp("Meal type", ["Breakfast", "Lunch", "Dinner"])
                ],
                required: ["date", "mealType"]
            ),
            makeFn(
                name: "buildShoppingListFromMealPlan",
                desc: "Generate shopping list(s) from planned recipe meals for a week — matkasse/freeform/eating-out slots are skipped since they don't need groceries.",
                props: [
                    "weekStartDate":  strProp("Any date within the target week, in YYYY-MM-DD format. Defaults to the current week if omitted."),
                    "oneListPerWeek": boolProp("True to create one list per week (only relevant for multi-week ranges elsewhere in the app); false merges everything into a single list. Defaults to false.")
                ],
                required: []
            ),
            makeFn(
                name: "createMatkasseBox",
                desc: "Add a matkasse / meal-kit delivery box for a delivery week. The provider name is whatever the user calls it — never assume a specific brand.",
                props: [
                    "provider":         strProp("Provider name as the user describes it, e.g. 'Adams Matkasse', 'our meal kit'"),
                    "deliveryWeek":     strProp("Delivery week date in YYYY-MM-DD format (any day in that week)"),
                    "numberOfMeals":    numProp("Number of meals included, if mentioned"),
                    "servingsPerMeal":  numProp("Servings per meal, if mentioned"),
                    "price":            numProp("Box price in NOK, if mentioned"),
                    "notes":            strProp("Optional notes")
                ],
                required: ["provider"]
            ),
            makeFn(
                name: "addMatkasseMeal",
                desc: "Add a meal to an existing matkasse box.",
                props: [
                    "boxProvider": strProp("Existing matkasse box's provider name"),
                    "mealTitle":   strProp("Meal title to add")
                ],
                required: ["boxProvider", "mealTitle"]
            ),
            makeFn(
                name: "updateMatkasseBox",
                desc: "Edit an existing matkasse box's details.",
                props: [
                    "existingProvider": strProp("Existing box's provider name"),
                    "newProvider":      strProp("New provider name, if changing it"),
                    "deliveryWeek":     strProp("New delivery week date in YYYY-MM-DD format, if changing it"),
                    "numberOfMeals":    numProp("New number of meals, if changing it"),
                    "servingsPerMeal":  numProp("New servings per meal, if changing it"),
                    "price":            numProp("New price in NOK, if changing it"),
                    "notes":            strProp("New notes, if changing them")
                ],
                required: ["existingProvider"]
            ),
            makeFn(
                name: "deleteMatkasseBox",
                desc: "Delete a matkasse box entirely, including its meals. Only use when the user clearly asks to remove it.",
                props: ["provider": strProp("Box's provider name to delete")],
                required: ["provider"]
            ),
            makeFn(
                name: "removeMatkasseMeal",
                desc: "Remove a meal from a matkasse box.",
                props: [
                    "boxProvider": strProp("Existing matkasse box's provider name"),
                    "mealTitle":   strProp("Meal title to remove")
                ],
                required: ["boxProvider", "mealTitle"]
            ),
            makeFn(
                name: "createMemory",
                desc: "Save a user preference, habit, restriction, or decision pattern. Only propose if the user explicitly states a preference.",
                props: [
                    "summary":          strProp("Natural language description, e.g. 'Prefers Tine milk over Q milk'"),
                    "category":         enumProp("Memory category", ["Hard Requirement", "Preference", "Habit", "Decision Pattern"]),
                    "strength":         enumProp("Constraint strength", ["Absolute", "Strong", "Preference", "Weak"]),
                    "sensitivityLevel": enumProp("Sensitivity", ["Standard", "Sensitive", "Health"])
                ],
                required: ["summary", "category"]
            ),
            makeFn(
                name: "createProduct",
                desc: "Add a new product to the catalogue.",
                props: [
                    "name":     strProp("Product name"),
                    "category": strProp("Category, e.g. Dairy, Meat, Vegetables"),
                    "unit":     enumProp("Default unit", ["g", "kg", "ml", "l", "stk", "pk"])
                ],
                required: ["name"]
            ),
            makeFn(
                name: "updateProduct",
                desc: "Edit an existing product's name, category, or default unit.",
                props: [
                    "existingName": strProp("Existing product name"),
                    "newName":      strProp("New name, if renaming"),
                    "category":     strProp("New category, if changing it"),
                    "unit":         enumProp("New default unit, if changing it", ["g", "kg", "ml", "l", "stk", "pk"])
                ],
                required: ["existingName"]
            ),
            makeFn(
                name: "deleteProduct",
                desc: "Delete a product from the catalogue. Only use when the user clearly asks to remove it.",
                props: ["name": strProp("Product name to delete")],
                required: ["name"]
            ),
            makeFn(
                name: "mergeProducts",
                desc: "Merge two products that are duplicates of each other (e.g. 'tomato' and 'tomatoes'). The source product's prices and aliases move to the target, and the source is deleted.",
                props: [
                    "sourceProductName": strProp("The duplicate product to absorb and delete"),
                    "targetProductName": strProp("The product that survives and keeps its name")
                ],
                required: ["sourceProductName", "targetProductName"]
            ),
            makeFn(
                name: "updatePriceObservation",
                desc: "Correct the most recently recorded price for a product (optionally at a specific store). Use when the user says they made a mistake or the price changed.",
                props: [
                    "productName":     strProp("Product name"),
                    "storeBranchName": strProp("Store to narrow down which price, if the product is priced at multiple stores"),
                    "newPrice":        numProp("Corrected price in NOK"),
                    "newQuantity":     numProp("Corrected package quantity, if changing it"),
                    "newUnit":         enumProp("Corrected unit, if changing it", ["g", "kg", "ml", "l", "stk", "pk"])
                ],
                required: ["productName"]
            ),
            makeFn(
                name: "deletePriceObservation",
                desc: "Delete the most recently recorded price for a product (optionally at a specific store). Only use when the user clearly asks to remove a recorded price.",
                props: [
                    "productName":     strProp("Product name"),
                    "storeBranchName": strProp("Store to narrow down which price, if the product is priced at multiple stores")
                ],
                required: ["productName"]
            ),
            makeFn(
                name: "confirmPriceObservation",
                desc: "Re-confirm that the most recently recorded price for a product is still accurate — records a fresh observation dated today with the same price.",
                props: [
                    "productName":     strProp("Product name"),
                    "storeBranchName": strProp("Store to narrow down which price, if the product is priced at multiple stores")
                ],
                required: ["productName"]
            ),
            makeFn(
                name: "flagCommunityPrice",
                desc: "Flag a community-sourced price as suspicious or incorrect.",
                props: [
                    "productName":     strProp("Product name"),
                    "storeBranchName": strProp("Store to narrow down which price, if the product is priced at multiple stores")
                ],
                required: ["productName"]
            ),
            makeFn(
                name: "addProductAlias",
                desc: "Add an alternate name (alias) a product is also known by, e.g. a store-specific name or receipt spelling.",
                props: [
                    "productName": strProp("Existing product name"),
                    "alias":       strProp("Alternate name to add")
                ],
                required: ["productName", "alias"]
            ),
            makeFn(
                name: "removeProductAlias",
                desc: "Remove a previously saved alias from a product.",
                props: [
                    "productName": strProp("Existing product name"),
                    "alias":       strProp("Alias to remove")
                ],
                required: ["productName", "alias"]
            ),
            makeFn(
                name: "setProductBarcode",
                desc: "Set or update a product's barcode.",
                props: [
                    "productName": strProp("Existing product name"),
                    "barcode":     strProp("Barcode value")
                ],
                required: ["productName", "barcode"]
            ),
            makeFn(
                name: "changeAppSetting",
                desc: "Change a shopping/optimization app setting.",
                props: [
                    "key": enumProp("Setting to change", [
                        "cheapestDefinition", "maxStoreCount", "minimumSavings",
                        "travelCostPerKm", "fixedStoreVisitCost", "communityPricingEnabled"
                    ]),
                    "value": strProp("New value: for cheapestDefinition use one of \(CheapestDefinition.allCases.map(\.rawValue).joined(separator: ", ")); for maxStoreCount an integer; for minimumSavings/travelCostPerKm/fixedStoreVisitCost a NOK number; for communityPricingEnabled 'true' or 'false'")
                ],
                required: ["key", "value"]
            ),
            makeFn(
                name: "createStore",
                desc: "Add a supermarket branch the user shops at or wants to track. Use for specific physical locations such as Rema 1000 Pindsle.",
                props: [
                    "chainName":  strProp("Supermarket chain, e.g. Rema 1000, Meny, Kiwi"),
                    "branchName": strProp("Specific branch, area, or location name, e.g. Pindsle"),
                    "address":    strProp("Optional address or area detail"),
                    "isEnabled":  boolProp("Whether this branch should be enabled for shopping plans")
                ],
                required: ["chainName", "branchName"]
            ),
            makeFn(
                name: "updateStore",
                desc: "Edit an existing supermarket branch by name. Use for renaming, moving to another chain, changing address, or toggling enabled state.",
                props: [
                    "existingStoreName": strProp("Existing branch display name, e.g. Rema 1000 Pindsle"),
                    "chainName":         strProp("New chain name if changing it"),
                    "branchName":        strProp("New branch/location name if changing it"),
                    "address":           strProp("New address or area detail if changing it"),
                    "isEnabled":         boolProp("Whether this branch should be enabled")
                ],
                required: ["existingStoreName"]
            ),
            makeFn(
                name: "deleteStore",
                desc: "Delete a saved supermarket branch. Only use when the user clearly asks to remove or delete it.",
                props: ["storeName": strProp("Saved branch display name to delete")],
                required: ["storeName"]
            ),
            makeFn(
                name: "setStoreEnabled",
                desc: "Enable or disable a saved supermarket branch for shopping plans without deleting it.",
                props: [
                    "storeName": strProp("Saved branch display name"),
                    "isEnabled": boolProp("True to enable, false to disable")
                ],
                required: ["storeName", "isEnabled"]
            )
        ]
    }

    // MARK: - Schema helpers

    private func makeFn(name: String, desc: String, props: [String: [String: Any]], required: [String]) -> [String: Any] {
        [
            "name": name,
            "description": desc,
            "parameters": [
                "type": "OBJECT",
                "properties": props,
                "required": required
            ] as [String: Any]
        ]
    }

    private func strProp(_ desc: String)  -> [String: Any] { ["type": "STRING",  "description": desc] }
    private func numProp(_ desc: String)  -> [String: Any] { ["type": "NUMBER",  "description": desc] }
    private func boolProp(_ desc: String) -> [String: Any] { ["type": "BOOLEAN", "description": desc] }
    private func enumProp(_ desc: String, _ values: [String]) -> [String: Any] {
        ["type": "STRING", "description": desc, "enum": values]
    }

    // MARK: - Response Parsing

    private func parseResponse(_ response: GeminiResponse) -> AIResponse {
        guard let candidate = response.candidates?.first,
              let content = candidate.content else {
            return AIResponse(textContent: nil, proposedActions: [], memoryProposals: [], error: .invalidResponse)
        }

        var textParts: [String] = []
        var actions: [ProposedAction] = []
        var memoryProposals: [MemoryProposal] = []

        for part in content.parts {
            if let text = part.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textParts.append(text)
            }
            if let fc = part.functionCall {
                switch parseFunctionCall(fc) {
                case .action(let a):   actions.append(a)
                case .memory(let m):   memoryProposals.append(m)
                case .none:            break
                }
            }
        }

        return AIResponse(
            textContent: textParts.isEmpty ? nil : textParts.joined(separator: "\n"),
            proposedActions: actions,
            memoryProposals: memoryProposals,
            error: nil
        )
    }

    private enum ParseResult { case action(ProposedAction), memory(MemoryProposal), none }

    private func parseFunctionCall(_ fc: GeminiFunctionCallResult) -> ParseResult {
        let args = fc.args ?? [:]

        switch fc.name {
        case "createPriceObservation":
            guard let product = args["productName"]?.stringValue,
                  let store   = args["storeBranchName"]?.stringValue,
                  let priceD  = args["price"]?.doubleValue else { return .none }

            let price      = Decimal(priceD)
            let quantity   = args["quantity"]?.doubleValue
            let unit       = args["unit"]?.stringValue.flatMap { MeasurementUnit(rawValue: $0) }
            let isPromo    = args["isPromotion"]?.boolValue ?? false
            let qtyLabel   = quantity.map { qty in " \(Int(qty))\(unit?.rawValue ?? "")" } ?? ""

            return .action(ProposedAction(
                type: .createPriceObservation,
                summary: "Add price: \(product) — kr \(formatDecimal(price))\(qtyLabel) at \(store)",
                payload: .createPriceObservation(
                    productName: product,
                    storeBranchName: store,
                    price: price,
                    quantity: quantity,
                    unit: unit,
                    isPromotion: isPromo,
                    date: Date()
                ),
                riskLevel: .low
            ))

        case "addShoppingListItem":
            guard let list    = args["listName"]?.stringValue,
                  let product = args["productName"]?.stringValue,
                  let qty     = args["quantity"]?.stringValue else { return .none }

            return .action(ProposedAction(
                type: .addShoppingListItem,
                summary: "Add \(qty) \(product) to \(list)",
                payload: .addShoppingListItem(listName: list, productName: product, quantity: qty, notes: args["notes"]?.stringValue),
                riskLevel: .low
            ))

        case "createShoppingList":
            guard let name = args["name"]?.stringValue else { return .none }
            return .action(ProposedAction(
                type: .createShoppingList,
                summary: "Create shopping list: \(name)",
                payload: .createShoppingList(name: name),
                riskLevel: .low
            ))

        case "updateShoppingList":
            guard let existingListName = args["existingListName"]?.stringValue else { return .none }
            let newName = args["newName"]?.stringValue
            let plannedDate = args["plannedDate"]?.stringValue.flatMap { Self.dateFormatter.date(from: $0) }
            var summary = "Update list: \(existingListName)"
            if let newName { summary = "Rename list \(existingListName) to \(newName)" }
            return .action(ProposedAction(
                type: .updateShoppingList,
                summary: summary,
                payload: .updateShoppingList(existingListName: existingListName, newName: newName, plannedDate: plannedDate),
                riskLevel: .low
            ))

        case "deleteShoppingList":
            guard let listName = args["listName"]?.stringValue else { return .none }
            return .action(ProposedAction(
                type: .deleteShoppingList,
                summary: "Delete list: \(listName)",
                payload: .deleteShoppingList(listName: listName),
                riskLevel: .high
            ))

        case "updateShoppingListItem":
            guard let list = args["listName"]?.stringValue,
                  let product = args["productName"]?.stringValue else { return .none }
            return .action(ProposedAction(
                type: .updateShoppingListItem,
                summary: "Update \(product) on \(list)",
                payload: .updateShoppingListItem(
                    listName: list,
                    productName: product,
                    newQuantity: args["newQuantity"]?.stringValue,
                    newNotes: args["newNotes"]?.stringValue
                ),
                riskLevel: .low
            ))

        case "completeShoppingListItem":
            guard let list = args["listName"]?.stringValue,
                  let product = args["productName"]?.stringValue else { return .none }
            let isCompleted = args["isCompleted"]?.boolValue ?? true
            return .action(ProposedAction(
                type: .completeShoppingListItem,
                summary: "\(isCompleted ? "Mark bought" : "Mark not bought"): \(product) on \(list)",
                payload: .completeShoppingListItem(listName: list, productName: product, isCompleted: isCompleted),
                riskLevel: .low
            ))

        case "removeShoppingListItem":
            guard let list = args["listName"]?.stringValue,
                  let product = args["productName"]?.stringValue else { return .none }
            return .action(ProposedAction(
                type: .removeShoppingListItem,
                summary: "Remove \(product) from \(list)",
                payload: .removeShoppingListItem(listName: list, productName: product),
                riskLevel: .medium
            ))

        case "setShoppingListStatus":
            guard let list = args["listName"]?.stringValue,
                  let status = args["status"]?.stringValue else { return .none }
            return .action(ProposedAction(
                type: .setShoppingListStatus,
                summary: "Set \(list) to \(status)",
                payload: .setShoppingListStatus(listName: list, status: status),
                riskLevel: .low
            ))

        case "optimizeShoppingList":
            guard let list = args["listName"]?.stringValue else { return .none }
            return .action(ProposedAction(
                type: .optimizeShoppingList,
                summary: "Optimize list: \(list)",
                payload: .optimizeShoppingList(listName: list),
                riskLevel: .low
            ))

        case "moveShoppingListItem":
            guard let list = args["listName"]?.stringValue,
                  let product = args["productName"]?.stringValue,
                  let storeBranch = args["storeBranchName"]?.stringValue else { return .none }
            return .action(ProposedAction(
                type: .moveShoppingListItem,
                summary: "Move \(product) to \(storeBranch)",
                payload: .moveShoppingListItem(listName: list, productName: product, storeBranchName: storeBranch),
                riskLevel: .low
            ))

        case "substituteShoppingListItem":
            guard let list = args["listName"]?.stringValue,
                  let product = args["productName"]?.stringValue,
                  let newProduct = args["newProductName"]?.stringValue else { return .none }
            return .action(ProposedAction(
                type: .substituteShoppingListItem,
                summary: "Substitute \(product) with \(newProduct) on \(list)",
                payload: .substituteShoppingListItem(listName: list, productName: product, newProductName: newProduct),
                riskLevel: .low
            ))

        case "addRecipeToShoppingList":
            guard let recipeName = args["recipeName"]?.stringValue,
                  let listName = args["listName"]?.stringValue else { return .none }
            return .action(ProposedAction(
                type: .addRecipeToShoppingList,
                summary: "Add \(recipeName) ingredients to \(listName)",
                payload: .addRecipeToShoppingList(recipeName: recipeName, listName: listName),
                riskLevel: .low
            ))

        case "updateRecipe":
            guard let existingTitle = args["existingTitle"]?.stringValue else { return .none }
            let newTitle = args["newTitle"]?.stringValue
            return .action(ProposedAction(
                type: .updateRecipe,
                summary: newTitle.map { "Rename recipe \(existingTitle) to \($0)" } ?? "Update recipe: \(existingTitle)",
                payload: .updateRecipe(
                    existingTitle: existingTitle,
                    newTitle: newTitle,
                    description: args["description"]?.stringValue,
                    servings: args["servings"]?.doubleValue.map { Int($0) }
                ),
                riskLevel: .low
            ))

        case "deleteRecipe":
            guard let title = args["title"]?.stringValue else { return .none }
            return .action(ProposedAction(
                type: .deleteRecipe,
                summary: "Delete recipe: \(title)",
                payload: .deleteRecipe(title: title),
                riskLevel: .high
            ))

        case "setMealPlanSlot":
            guard let dateString = args["date"]?.stringValue,
                  let date = Self.dateFormatter.date(from: dateString),
                  let mealType = args["mealType"]?.stringValue else { return .none }
            let recipeTitle = args["recipeTitle"]?.stringValue
            let freeformText = args["freeformText"]?.stringValue
            let isEatingOut = args["isEatingOut"]?.boolValue ?? false
            let what = recipeTitle ?? (isEatingOut ? "eating out" : (freeformText ?? "a meal"))
            return .action(ProposedAction(
                type: .setMealPlanSlot,
                summary: "Plan \(mealType) on \(dateString): \(what)",
                payload: .setMealPlanSlot(
                    date: date,
                    mealType: mealType,
                    recipeTitle: recipeTitle,
                    freeformText: freeformText,
                    isEatingOut: isEatingOut,
                    isLeftover: args["isLeftover"]?.boolValue ?? false
                ),
                riskLevel: .low
            ))

        case "removeMealPlanSlot":
            guard let dateString = args["date"]?.stringValue,
                  let date = Self.dateFormatter.date(from: dateString),
                  let mealType = args["mealType"]?.stringValue else { return .none }
            return .action(ProposedAction(
                type: .removeMealPlanSlot,
                summary: "Remove planned \(mealType) on \(dateString)",
                payload: .removeMealPlanSlot(date: date, mealType: mealType),
                riskLevel: .medium
            ))

        case "buildShoppingListFromMealPlan":
            let weekStartDate = args["weekStartDate"]?.stringValue.flatMap { Self.dateFormatter.date(from: $0) }
            let oneListPerWeek = args["oneListPerWeek"]?.boolValue ?? false
            return .action(ProposedAction(
                type: .buildShoppingListFromMealPlan,
                summary: "Build shopping list from meal plan",
                payload: .buildShoppingListFromMealPlan(weekStartDate: weekStartDate, oneListPerWeek: oneListPerWeek),
                riskLevel: .low
            ))

        case "createMatkasseBox":
            guard let provider = args["provider"]?.stringValue else { return .none }
            let deliveryWeek = args["deliveryWeek"]?.stringValue.flatMap { Self.dateFormatter.date(from: $0) }
            return .action(ProposedAction(
                type: .createMatkasseBox,
                summary: "Add matkasse box: \(provider)",
                payload: .createMatkasseBox(
                    provider: provider,
                    deliveryWeek: deliveryWeek,
                    numberOfMeals: args["numberOfMeals"]?.doubleValue.map { Int($0) },
                    servingsPerMeal: args["servingsPerMeal"]?.doubleValue.map { Int($0) },
                    price: args["price"]?.doubleValue.map { Decimal($0) },
                    notes: args["notes"]?.stringValue
                ),
                riskLevel: .low
            ))

        case "addMatkasseMeal":
            guard let boxProvider = args["boxProvider"]?.stringValue,
                  let mealTitle = args["mealTitle"]?.stringValue else { return .none }
            return .action(ProposedAction(
                type: .addMatkasseMeal,
                summary: "Add \(mealTitle) to \(boxProvider) box",
                payload: .addMatkasseMeal(boxProvider: boxProvider, mealTitle: mealTitle),
                riskLevel: .low
            ))

        case "updateMatkasseBox":
            guard let existingProvider = args["existingProvider"]?.stringValue else { return .none }
            let newProvider = args["newProvider"]?.stringValue
            let deliveryWeek = args["deliveryWeek"]?.stringValue.flatMap { Self.dateFormatter.date(from: $0) }
            return .action(ProposedAction(
                type: .updateMatkasseBox,
                summary: newProvider.map { "Rename matkasse box \(existingProvider) to \($0)" } ?? "Update matkasse box: \(existingProvider)",
                payload: .updateMatkasseBox(
                    existingProvider: existingProvider,
                    newProvider: newProvider,
                    deliveryWeek: deliveryWeek,
                    numberOfMeals: args["numberOfMeals"]?.doubleValue.map { Int($0) },
                    servingsPerMeal: args["servingsPerMeal"]?.doubleValue.map { Int($0) },
                    price: args["price"]?.doubleValue.map { Decimal($0) },
                    notes: args["notes"]?.stringValue
                ),
                riskLevel: .low
            ))

        case "deleteMatkasseBox":
            guard let provider = args["provider"]?.stringValue else { return .none }
            return .action(ProposedAction(
                type: .deleteMatkasseBox,
                summary: "Delete matkasse box: \(provider)",
                payload: .deleteMatkasseBox(provider: provider),
                riskLevel: .high
            ))

        case "removeMatkasseMeal":
            guard let boxProvider = args["boxProvider"]?.stringValue,
                  let mealTitle = args["mealTitle"]?.stringValue else { return .none }
            return .action(ProposedAction(
                type: .removeMatkasseMeal,
                summary: "Remove \(mealTitle) from \(boxProvider) box",
                payload: .removeMatkasseMeal(boxProvider: boxProvider, mealTitle: mealTitle),
                riskLevel: .medium
            ))

        case "createMemory":
            guard let summary  = args["summary"]?.stringValue,
                  let catStr   = args["category"]?.stringValue else { return .none }

            let category    = MemoryCategory(rawValue: catStr) ?? .preference
            let strength    = args["strength"]?.stringValue.flatMap { ConstraintStrength(rawValue: $0) } ?? .preference
            let sensitivity = args["sensitivityLevel"]?.stringValue.flatMap { SensitivityLevel(rawValue: $0) } ?? .standard

            let memory = AIMemory(summary: summary, category: category, strength: strength, sensitivityLevel: sensitivity)
            return .memory(MemoryProposal(memory: memory, reason: "Based on what you mentioned"))

        case "createProduct":
            guard let name = args["name"]?.stringValue else { return .none }
            let unit = args["unit"]?.stringValue.flatMap { MeasurementUnit(rawValue: $0) }
            return .action(ProposedAction(
                type: .createProduct,
                summary: "Add product: \(name)",
                payload: .createProduct(name: name, category: args["category"]?.stringValue, unit: unit),
                riskLevel: .low
            ))

        case "updateProduct":
            guard let existingName = args["existingName"]?.stringValue else { return .none }
            let newName = args["newName"]?.stringValue
            let unit = args["unit"]?.stringValue.flatMap { MeasurementUnit(rawValue: $0) }
            return .action(ProposedAction(
                type: .updateProduct,
                summary: newName.map { "Rename product \(existingName) to \($0)" } ?? "Update product: \(existingName)",
                payload: .updateProduct(existingName: existingName, newName: newName, category: args["category"]?.stringValue, unit: unit),
                riskLevel: .low
            ))

        case "deleteProduct":
            guard let name = args["name"]?.stringValue else { return .none }
            return .action(ProposedAction(
                type: .deleteProduct,
                summary: "Delete product: \(name)",
                payload: .deleteProduct(name: name),
                riskLevel: .high
            ))

        case "mergeProducts":
            guard let source = args["sourceProductName"]?.stringValue,
                  let target = args["targetProductName"]?.stringValue else { return .none }
            return .action(ProposedAction(
                type: .mergeProducts,
                summary: "Merge \(source) into \(target)",
                payload: .mergeProducts(sourceProductName: source, targetProductName: target),
                riskLevel: .high
            ))

        case "updatePriceObservation":
            guard let product = args["productName"]?.stringValue else { return .none }
            let store = args["storeBranchName"]?.stringValue
            let newPriceD = args["newPrice"]?.doubleValue
            let unit = args["newUnit"]?.stringValue.flatMap { MeasurementUnit(rawValue: $0) }
            return .action(ProposedAction(
                type: .updatePriceObservation,
                summary: "Update price: \(product)" + (store.map { " at \($0)" } ?? ""),
                payload: .updatePriceObservation(
                    productName: product,
                    storeBranchName: store,
                    newPrice: newPriceD.map { Decimal($0) },
                    newQuantity: args["newQuantity"]?.doubleValue,
                    newUnit: unit
                ),
                riskLevel: .low
            ))

        case "deletePriceObservation":
            guard let product = args["productName"]?.stringValue else { return .none }
            let store = args["storeBranchName"]?.stringValue
            return .action(ProposedAction(
                type: .deletePriceObservation,
                summary: "Delete price: \(product)" + (store.map { " at \($0)" } ?? ""),
                payload: .deletePriceObservation(productName: product, storeBranchName: store),
                riskLevel: .medium
            ))

        case "confirmPriceObservation":
            guard let product = args["productName"]?.stringValue else { return .none }
            let store = args["storeBranchName"]?.stringValue
            return .action(ProposedAction(
                type: .confirmPriceObservation,
                summary: "Confirm price still accurate: \(product)" + (store.map { " at \($0)" } ?? ""),
                payload: .confirmPriceObservation(productName: product, storeBranchName: store),
                riskLevel: .low
            ))

        case "flagCommunityPrice":
            guard let product = args["productName"]?.stringValue else { return .none }
            let store = args["storeBranchName"]?.stringValue
            return .action(ProposedAction(
                type: .flagCommunityPrice,
                summary: "Flag community price: \(product)" + (store.map { " at \($0)" } ?? ""),
                payload: .flagCommunityPrice(productName: product, storeBranchName: store),
                riskLevel: .low
            ))

        case "addProductAlias":
            guard let product = args["productName"]?.stringValue,
                  let alias = args["alias"]?.stringValue else { return .none }
            return .action(ProposedAction(
                type: .addProductAlias,
                summary: "Add alias \"\(alias)\" to \(product)",
                payload: .addProductAlias(productName: product, alias: alias),
                riskLevel: .low
            ))

        case "removeProductAlias":
            guard let product = args["productName"]?.stringValue,
                  let alias = args["alias"]?.stringValue else { return .none }
            return .action(ProposedAction(
                type: .removeProductAlias,
                summary: "Remove alias \"\(alias)\" from \(product)",
                payload: .removeProductAlias(productName: product, alias: alias),
                riskLevel: .low
            ))

        case "setProductBarcode":
            guard let product = args["productName"]?.stringValue,
                  let barcode = args["barcode"]?.stringValue else { return .none }
            return .action(ProposedAction(
                type: .setProductBarcode,
                summary: "Set barcode for \(product)",
                payload: .setProductBarcode(productName: product, barcode: barcode),
                riskLevel: .low
            ))

        case "changeAppSetting":
            guard let key = args["key"]?.stringValue,
                  let value = args["value"]?.stringValue else { return .none }
            return .action(ProposedAction(
                type: .changeAppSetting,
                summary: "Change setting: \(key) → \(value)",
                payload: .changeAppSetting(key: key, value: value),
                riskLevel: .low
            ))

        case "createStore":
            guard let chainName = args["chainName"]?.stringValue,
                  let branchName = args["branchName"]?.stringValue else { return .none }
            let isEnabled = args["isEnabled"]?.boolValue ?? true
            return .action(ProposedAction(
                type: .createStore,
                summary: "Add store: \(chainName) \(branchName)",
                payload: .createStore(chainName: chainName, branchName: branchName, address: args["address"]?.stringValue, isEnabled: isEnabled),
                riskLevel: .low
            ))

        case "updateStore":
            guard let existingStoreName = args["existingStoreName"]?.stringValue else { return .none }
            return .action(ProposedAction(
                type: .updateStore,
                summary: "Update store: \(existingStoreName)",
                payload: .updateStore(
                    existingStoreName: existingStoreName,
                    chainName: args["chainName"]?.stringValue,
                    branchName: args["branchName"]?.stringValue,
                    address: args["address"]?.stringValue,
                    isEnabled: args["isEnabled"]?.boolValue
                ),
                riskLevel: .medium
            ))

        case "deleteStore":
            guard let storeName = args["storeName"]?.stringValue else { return .none }
            return .action(ProposedAction(
                type: .deleteStore,
                summary: "Delete store: \(storeName)",
                payload: .deleteStore(storeName: storeName),
                riskLevel: .high
            ))

        case "setStoreEnabled":
            guard let storeName = args["storeName"]?.stringValue,
                  let isEnabled = args["isEnabled"]?.boolValue else { return .none }
            return .action(ProposedAction(
                type: isEnabled ? .enableStore : .disableStore,
                summary: "\(isEnabled ? "Enable" : "Disable") store: \(storeName)",
                payload: .setStoreEnabled(storeName: storeName, isEnabled: isEnabled),
                riskLevel: .low
            ))

        default:
            return .none
        }
    }

    private func formatDecimal(_ d: Decimal) -> String {
        let n = NSDecimalNumber(decimal: d)
        return n.stringValue
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}

private extension KeyedDecodingContainer {
    func decodeFirstPresentString(for keys: [Key]) throws -> String? {
        for key in keys {
            if let value = try decodeIfPresent(String.self, forKey: key),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }
}

private struct GeminiOnboardingTurn: Decodable {
    let assistantText: String
    let decision: String
    let normalizedAnswer: String?
    let settings: GeminiOnboardingSettings?
    let stores: [GeminiOnboardingStore]?
    let memories: [GeminiOnboardingMemory]?
    let products: [GeminiOnboardingProduct]?

    enum CodingKeys: String, CodingKey {
        case assistantText
        case assistant_text
        case message
        case response
        case decision
        case normalizedAnswer
        case normalized_answer
        case settings
        case stores
        case memories
        case products
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assistantText = try container.decodeFirstPresentString(for: [.assistantText, .assistant_text, .message, .response]) ?? "Got it. I've updated setup with that."
        decision = try container.decodeIfPresent(String.self, forKey: .decision) ?? "advance"
        normalizedAnswer = try container.decodeFirstPresentString(for: [.normalizedAnswer, .normalized_answer])
        settings = try container.decodeIfPresent(GeminiOnboardingSettings.self, forKey: .settings)
        stores = try container.decodeIfPresent([GeminiOnboardingStore].self, forKey: .stores)
        memories = try container.decodeIfPresent([GeminiOnboardingMemory].self, forKey: .memories)
        products = try container.decodeIfPresent([GeminiOnboardingProduct].self, forKey: .products)
    }

    func result(defaultAnswer: String) -> OnboardingAIResult {
        let actions = storeActions + productActions + settingActions
        let memoryProposals = (memories ?? []).compactMap { $0.memoryProposal }
        return OnboardingAIResult(
            assistantText: assistantText,
            shouldAdvance: decision != "followUp",
            normalizedAnswer: normalizedAnswer ?? (decision == "skip" ? "Skipped for now" : defaultAnswer),
            proposedActions: actions,
            memoryProposals: memoryProposals
        )
    }

    private var storeActions: [ProposedAction] {
        (stores ?? []).compactMap { store in
            guard let chainName = store.chainName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let branchName = store.branchName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !chainName.isEmpty,
                  !branchName.isEmpty else { return nil }
            return ProposedAction(
                type: .createStore,
                summary: "Add store: \(chainName) \(branchName)",
                payload: .createStore(
                    chainName: chainName,
                    branchName: branchName,
                    address: store.address,
                    isEnabled: store.isEnabled ?? true
                ),
                riskLevel: .low,
                requiresConfirmation: false
            )
        }
    }

    private var productActions: [ProposedAction] {
        (products ?? []).compactMap { product in
            guard let name = product.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
            let unit = product.unit.flatMap { MeasurementUnit(rawValue: $0) }
            return ProposedAction(
                type: .createProduct,
                summary: "Add product: \(name)",
                payload: .createProduct(name: name, category: product.category, unit: unit),
                riskLevel: .low,
                requiresConfirmation: false
            )
        }
    }

    private var settingActions: [ProposedAction] {
        guard let settings else { return [] }
        var actions: [ProposedAction] = []
        if let cheapestDefinition = settings.cheapestDefinition {
            actions.append(ProposedAction(
                type: .changeAppSetting,
                summary: "Set cheapest strategy: \(cheapestDefinition)",
                payload: .changeAppSetting(key: "cheapestDefinition", value: cheapestDefinition),
                riskLevel: .low,
                requiresConfirmation: false
            ))
        }
        if let maxStoreCount = settings.maxStoreCount {
            actions.append(ProposedAction(
                type: .changeAppSetting,
                summary: "Set max stores: \(maxStoreCount)",
                payload: .changeAppSetting(key: "maxStoreCount", value: String(maxStoreCount)),
                riskLevel: .low,
                requiresConfirmation: false
            ))
        }
        if let minimumSavings = settings.minimumSavings {
            actions.append(ProposedAction(
                type: .changeAppSetting,
                summary: "Set extra-store saving threshold: kr \(minimumSavings)",
                payload: .changeAppSetting(key: "minimumSavings", value: String(minimumSavings)),
                riskLevel: .low,
                requiresConfirmation: false
            ))
        }
        return actions
    }
}

private struct GeminiOnboardingSettings: Decodable {
    let cheapestDefinition: String?
    let maxStoreCount: Int?
    let minimumSavings: Double?
}

private struct GeminiOnboardingStore: Decodable {
    let chainName: String?
    let branchName: String?
    let address: String?
    let isEnabled: Bool?
}

private struct GeminiOnboardingMemory: Decodable {
    let summary: String?
    let category: String?
    let strength: String?
    let sensitivityLevel: String?

    var memoryProposal: MemoryProposal? {
        guard let trimmed = summary?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        let memory = AIMemory(
            summary: trimmed,
            category: category.flatMap { MemoryCategory(rawValue: $0) } ?? .preference,
            strength: strength.flatMap { ConstraintStrength(rawValue: $0) } ?? .preference,
            sensitivityLevel: sensitivityLevel.flatMap { SensitivityLevel(rawValue: $0) } ?? .standard
        )
        return MemoryProposal(memory: memory, reason: "Captured during onboarding.")
    }
}

private struct GeminiOnboardingProduct: Decodable {
    let name: String?
    let category: String?
    let unit: String?
}

private struct GeminiReceiptParse: Decodable {
    let inferredStoreName: String?
    let lines: [GeminiReceiptLine]

    func parsedReceipt(knownProducts: [Product]) -> ParsedReceipt {
        let receiptLines = lines.map { line in
            let matchedProduct = line.productName.flatMap { productName in
                knownProducts.first { $0.name.localizedCaseInsensitiveCompare(productName) == .orderedSame }
            }
            let productName = matchedProduct?.name ?? line.productName
            return ReceiptLine(
                rawText: line.rawText,
                productName: productName,
                matchedProductID: matchedProduct?.id,
                price: line.price.map { Decimal($0) },
                isIncluded: line.include && productName != nil && line.price != nil
            )
        }

        return ParsedReceipt(
            inferredStoreName: inferredStoreName?.nilIfBlank,
            observedDate: Date(),
            lines: receiptLines
        )
    }
}

private struct GeminiReceiptLine: Decodable {
    let rawText: String
    let productName: String?
    let price: Double?
    let include: Bool

    enum CodingKeys: String, CodingKey {
        case rawText
        case raw_text
        case productName
        case product_name
        case price
        case include
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rawText = try container.decodeFirstPresentString(for: [.rawText, .raw_text]) ?? ""
        productName = try container.decodeFirstPresentString(for: [.productName, .product_name])
        price = try container.decodeIfPresent(Double.self, forKey: .price)
        include = try container.decodeIfPresent(Bool.self, forKey: .include) ?? (productName != nil && price != nil)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
