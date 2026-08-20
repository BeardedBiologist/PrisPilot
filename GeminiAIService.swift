import Foundation

// Gemini Developer API via REST — no SDK dependency needed.
// Key is read from Keychain; never embedded in source.

final class GeminiAIService: AIService {
    let providerName: String
    var isAvailable: Bool = true

    private let apiKey: String
    private let model: String
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    init(apiKey: String, model: String = "gemini-3.5-flash-lite") {
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
        let url = URL(string: "\(baseURL)/\(model):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try buildRequestBody(messages: messages, context: context)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200: break
            case 401, 403: throw AIServiceError.invalidAPIKey
            case 429:      throw AIServiceError.quotaExhausted
            default:
                throw parseHTTPError(statusCode: http.statusCode, data: data)
            }
        }

        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)

        if let error = geminiResponse.error {
            if error.status == "RESOURCE_EXHAUSTED" { throw AIServiceError.quotaExhausted }
            if error.status == "UNAUTHENTICATED"    { throw AIServiceError.invalidAPIKey }
            throw AIServiceError.unknown(error.message)
        }

        return parseResponse(geminiResponse)
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
            return .unknown(error.message)
        }

        let body = String(data: data, encoding: .utf8) ?? "No response body"
        return .unknown("HTTP \(statusCode): \(body.prefix(200))")
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
            "CRITICAL: Never perform actions directly. Use tools to PROPOSE changes. The user approves all proposals before execution.",
            "- Group related actions in one response (e.g. record a price AND add to list if user implies both).",
            "- Propose memory separately from shopping actions.",
            "- Keep text responses concise; let the proposed actions do the heavy lifting.",
            "- For prices, include quantity and unit when mentioned."
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

        default:
            return .none
        }
    }

    private func formatDecimal(_ d: Decimal) -> String {
        let n = NSDecimalNumber(decimal: d)
        return n.stringValue
    }
}
