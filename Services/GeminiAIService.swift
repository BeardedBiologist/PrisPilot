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
