import Foundation

// Parses pasted recipe text from any web source into a structured recipe.
// Handles RecipeTin Eats, AllRecipes, BBC Good Food, NYT Cooking, and others
// without requiring AI — keeping the chat response instant.

enum RecipeTextParser {

    struct ParsedRecipe {
        var title: String
        var description: String?
        var author: String?
        var prepTimeMinutes: Int?
        var cookTimeMinutes: Int?
        var servings: Int
        var ingredients: [RecipeIngredient]
        var steps: [String]
        var tags: [String]
    }

    // MARK: - Detection

    static func isLikelyRecipe(_ text: String) -> Bool {
        guard text.count > 150 else { return false }
        let lower = text.lowercased()
        let hasIngredients = ingredientHeaders.contains { lower.contains($0) }
        let hasStructure = instructionHeaders.contains { lower.contains($0) } || text.contains("▢")
        return hasIngredients && hasStructure
    }

    static func localRecipeImport(for text: String) -> AIResponse? {
        guard isLikelyRecipe(text) else { return nil }
        let parsed = parse(text)

        let summary = parsed.ingredients.isEmpty
            ? "Create recipe: \(parsed.title)"
            : "Create recipe: \(parsed.title) with \(parsed.ingredients.count) ingredients"

        let action = ProposedAction(
            type: .createRecipe,
            summary: summary,
            payload: .createRecipe(
                title: parsed.title,
                description: parsed.description,
                servings: parsed.servings,
                ingredients: parsed.ingredients,
                steps: parsed.steps,
                tags: parsed.tags,
                author: parsed.author,
                prepTimeMinutes: parsed.prepTimeMinutes,
                cookTimeMinutes: parsed.cookTimeMinutes
            ),
            riskLevel: .low
        )

        return AIResponse(
            textContent: "I found a recipe in your message and extracted it locally — no need to wait for AI. Confirm below to save it.",
            proposedActions: [action],
            memoryProposals: [],
            error: nil
        )
    }

    // MARK: - Section Header Vocabularies

    private static let ingredientHeaders = [
        "ingredients", "what you'll need", "you will need", "you'll need", "what you need"
    ]

    private static let instructionHeaders = [
        "instructions", "method", "directions", "steps", "how to make", "preparation",
        "how to prepare", "to make", "procedure"
    ]

    private static let notesHeaders = [
        "recipe notes", "notes:", "tips:", "chef's notes", "cook's notes",
        "note:", "tips and notes"
    ]

    // MARK: - Main Parser

    static func parse(_ text: String) -> ParsedRecipe {
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        let ingredientsIdx = firstIndex(of: ingredientHeaders, in: lines)
        let instructionsIdx = firstIndex(of: instructionHeaders, in: lines)
        let notesIdx = firstIndex(of: notesHeaders, in: lines)

        let iEnd = min(ingredientsIdx ?? lines.count, lines.count)
        let inEnd = min(instructionsIdx ?? lines.count, lines.count)
        let nEnd = min(notesIdx ?? lines.count, lines.count)

        let headerLines = Array(lines[0..<iEnd])
        let ingredientLines: [String] = {
            guard let start = ingredientsIdx, start + 1 < inEnd else { return [] }
            return Array(lines[(start + 1)..<inEnd])
        }()
        let stepLines: [String] = {
            guard let start = instructionsIdx, start + 1 < nEnd else { return [] }
            return Array(lines[(start + 1)..<nEnd])
        }()

        return ParsedRecipe(
            title: parseTitle(from: headerLines),
            description: parseDescription(from: headerLines),
            author: parseAuthor(from: headerLines),
            prepTimeMinutes: parseTime(keyword: "prep", from: headerLines),
            cookTimeMinutes: parseTime(keyword: "cook", from: headerLines),
            servings: parseServings(from: headerLines),
            ingredients: parseIngredients(from: ingredientLines),
            steps: parseSteps(from: stepLines),
            tags: parseTags(from: headerLines)
        )
    }

    // MARK: - Header Field Parsers

    private static func parseTitle(from lines: [String]) -> String {
        lines.first(where: { !$0.isEmpty }) ?? "Untitled Recipe"
    }

    private static func parseAuthor(from lines: [String]) -> String? {
        let authorPatterns = ["author:", "by ", "recipe by "]
        for line in lines.prefix(8) {
            let lower = line.lowercased()
            for pat in authorPatterns {
                guard let range = lower.range(of: pat) else { continue }
                let after = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                let name = after
                    .components(separatedBy: "  ").first?
                    .components(separatedBy: "|").first?
                    .trimmingCharacters(in: .whitespaces) ?? after
                if !name.isEmpty && name.count < 60 { return name }
            }
        }
        return nil
    }

    private static func parseTime(keyword: String, from lines: [String]) -> Int? {
        let patterns = [
            "\(keyword) time:?\\s*(\\d+)",
            "\(keyword):?\\s*(\\d+)"
        ]
        for line in lines {
            let lower = line.lowercased()
            for pattern in patterns {
                guard let range = lower.range(of: pattern, options: .regularExpression) else { continue }
                let match = String(lower[range])
                if let numRange = match.range(of: "\\d+", options: .regularExpression),
                   let n = Int(match[numRange]) {
                    return n
                }
            }
        }
        return nil
    }

    private static func parseServings(from lines: [String]) -> Int {
        let patterns = [
            "(?:serves?|servings?|makes?|yield):?\\s*(\\d+)",
            "servings(\\d+)"
        ]
        for line in lines.prefix(10) {
            let lower = line.lowercased()
            for pattern in patterns {
                guard let range = lower.range(of: pattern, options: .regularExpression) else { continue }
                let match = String(lower[range])
                if let numRange = match.range(of: "\\d+", options: .regularExpression),
                   let n = Int(match[numRange]), n > 0 {
                    return min(n, 200)
                }
            }
        }
        return 4
    }

    private static func parseTags(from lines: [String]) -> [String] {
        var tags: [String] = []
        for line in lines.prefix(6) {
            let fields = line.components(separatedBy: "  ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for field in fields {
                let lower = field.lowercased()
                guard !lower.hasPrefix("author") && !lower.contains("prep") &&
                      !lower.contains("cook") && !lower.contains("total") &&
                      !lower.contains("min") && !lower.contains("vote") &&
                      !lower.contains("serving") && !lower.contains("scale") &&
                      !lower.contains("print") && !field.contains(":") else { continue }

                if field.contains(",") {
                    let parts = field.components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty && $0.count < 40 && !$0.contains(where: { $0.isNumber }) }
                    if parts.count >= 2 { tags.append(contentsOf: parts) }
                } else if field.count > 2 && field.count < 30 &&
                          !field.contains(where: { $0.isNumber }) &&
                          field.split(separator: " ").count <= 3 &&
                          field.first?.isLetter == true {
                    tags.append(field)
                }
            }
        }
        var seen = Set<String>()
        return tags.filter { seen.insert($0.lowercased()).inserted }
    }

    private static func parseDescription(from lines: [String]) -> String? {
        var paragraphs: [String] = []
        var pastTitle = false
        for line in lines {
            guard !line.isEmpty else { continue }
            if !pastTitle { pastTitle = true; continue }

            let lower = line.lowercased()
            if lower.contains("author:") || lower.contains("prep:") || lower.contains("cook:") { continue }
            if lower.contains("votes") || lower.contains("serving") || lower.hasPrefix("print") { continue }
            if lower.hasPrefix("recipe video") || lower.hasPrefix("cook mode") { continue }
            if lower.contains("tap or hover") || lower.contains("prevent screen") { continue }
            if line.hasPrefix("▢") || line.hasPrefix("•") || line.hasPrefix("- ") { continue }
            if line.count < 20 { continue }

            paragraphs.append(line)
        }
        let result = paragraphs.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    // MARK: - Ingredient Parsing

    private static func parseIngredients(from lines: [String]) -> [RecipeIngredient] {
        lines.compactMap { parseIngredientLine($0) }
    }

    static func parseIngredientLine(_ rawLine: String) -> RecipeIngredient? {
        var text = rawLine.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        // Strip bullet prefix
        let bullets = ["▢", "•", "◦", "◉", "●", "–", "—", "→"]
        var hasBullet = false
        for b in bullets {
            if text.hasPrefix(b) {
                text = String(text.dropFirst(b.count)).trimmingCharacters(in: .whitespaces)
                hasBullet = true
                break
            }
        }
        if !hasBullet {
            if text.hasPrefix("- ") { text = String(text.dropFirst(2)).trimmingCharacters(in: .whitespaces); hasBullet = true }
            else if text.hasPrefix("* ") { text = String(text.dropFirst(2)).trimmingCharacters(in: .whitespaces); hasBullet = true }
        }

        // If there's no bullet, only parse if the line starts with a digit/fraction (quantity-first format)
        if !hasBullet {
            let startsWithQuantity = text.first?.isNumber == true ||
                ["½","¼","¾","⅓","⅔","⅛","⅜","⅝","⅞"].contains(where: { text.hasPrefix($0) })
            guard startsWithQuantity else { return nil }
        }

        guard !text.isEmpty else { return nil }

        // Clean noise
        text = text
            .replacingOccurrences(of: #"\(Note \d+\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\(optional\)"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)

        // Prefer metric: "5 oz / 150g bacon" → "150g bacon"
        text = preferMetric(in: text)

        let (qty, unit, nameRaw) = extractQuantityAndUnit(from: text)

        var name = nameRaw.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        name = name.replacingOccurrences(of: #"\([^)]{0,80}\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if let comma = name.firstIndex(of: ",") {
            name = String(name[name.startIndex..<comma]).trimmingCharacters(in: .whitespaces)
        }

        guard !name.isEmpty, name.count > 1 else { return nil }

        return RecipeIngredient(productName: name, quantity: qty ?? 1.0, unit: unit ?? .pieces)
    }

    private static func preferMetric(in text: String) -> String {
        let pattern = #"^.+?\s*/\s*(\d+(?:\.\d+)?)\s*(g|kg|ml|l)\b(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return text }
        func grp(_ i: Int) -> String {
            let r = m.range(at: i)
            guard r.location != NSNotFound, let sr = Range(r, in: text) else { return "" }
            return String(text[sr])
        }
        let qty = grp(1); let unit = grp(2); let rest = grp(3)
        guard !qty.isEmpty else { return text }
        return "\(qty)\(unit)\(rest)"
    }

    private static func extractQuantityAndUnit(from text: String) -> (Double?, MeasurementUnit?, String) {
        var remaining = text
        let (qty, afterQty) = parseLeadingNumber(from: remaining)
        if qty != nil { remaining = afterQty }

        let units: [(String, MeasurementUnit, Double)] = [
            ("tablespoons", .millilitres, 15), ("tablespoon", .millilitres, 15),
            ("tbsps", .millilitres, 15), ("tbsp", .millilitres, 15),
            ("teaspoons", .millilitres, 5), ("teaspoon", .millilitres, 5),
            ("tsps", .millilitres, 5), ("tsp", .millilitres, 5),
            ("cups", .millilitres, 240), ("cup", .millilitres, 240),
            ("pounds", .grams, 454), ("pound", .grams, 454),
            ("lbs", .grams, 454), ("lb", .grams, 454),
            ("ounces", .grams, 28), ("ounce", .grams, 28), ("oz", .grams, 28),
            ("kilograms", .kilograms, 1), ("kilogram", .kilograms, 1), ("kg", .kilograms, 1),
            ("grams", .grams, 1), ("gram", .grams, 1), ("g", .grams, 1),
            ("millilitres", .millilitres, 1), ("milliliters", .millilitres, 1),
            ("millilitre", .millilitres, 1), ("milliliter", .millilitres, 1), ("ml", .millilitres, 1),
            ("litres", .litres, 1), ("liters", .litres, 1),
            ("litre", .litres, 1), ("liter", .litres, 1), ("dl", .millilitres, 100),
            ("packets", .packs, 1), ("packet", .packs, 1), ("packs", .packs, 1), ("pack", .packs, 1),
            ("cloves", .pieces, 1), ("clove", .pieces, 1),
            ("stalks", .pieces, 1), ("stalk", .pieces, 1),
            ("sheets", .pieces, 1), ("sheet", .pieces, 1),
            ("slices", .pieces, 1), ("slice", .pieces, 1),
            ("cans", .pieces, 1), ("can", .pieces, 1),
            ("bunches", .pieces, 1), ("bunch", .pieces, 1),
            ("sprigs", .pieces, 1), ("sprig", .pieces, 1),
            ("pieces", .pieces, 1), ("piece", .pieces, 1),
            ("large", .pieces, 1), ("medium", .pieces, 1), ("small", .pieces, 1),
        ]

        let trimmed = remaining.trimmingCharacters(in: .whitespaces)
        for (token, baseUnit, factor) in units {
            let escaped = NSRegularExpression.escapedPattern(for: token)
            if let range = trimmed.range(of: "^\(escaped)\\b", options: [.regularExpression, .caseInsensitive]) {
                let name = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                return (qty.map { $0 * factor }, baseUnit, name)
            }
        }

        return (qty, nil, trimmed)
    }

    private static func parseLeadingNumber(from text: String) -> (Double?, String) {
        let t = text.trimmingCharacters(in: .whitespaces)

        let unicodeFracs: [(String, Double)] = [
            ("½", 0.5), ("¼", 0.25), ("¾", 0.75), ("⅓", 1.0/3), ("⅔", 2.0/3),
            ("⅛", 0.125), ("⅜", 0.375), ("⅝", 0.625), ("⅞", 0.875)
        ]
        for (s, v) in unicodeFracs {
            if t.hasPrefix(s) { return (v, String(t.dropFirst(s.count))) }
        }

        // Mixed number "2 1/2 "
        if let r = t.range(of: #"^(\d+)\s+(\d+)/(\d+)\s"#, options: .regularExpression) {
            let parts = String(t[r]).trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
            if parts.count == 2, let whole = Double(parts[0]) {
                let frac = parts[1].components(separatedBy: "/")
                if frac.count == 2, let n = Double(frac[0]), let d = Double(frac[1]), d > 0 {
                    return (whole + n / d, String(t[r.upperBound...]))
                }
            }
        }

        // Fraction "1/2 "
        if let r = t.range(of: #"^(\d+)/(\d+)\s"#, options: .regularExpression) {
            let parts = String(t[r]).trimmingCharacters(in: .whitespaces).components(separatedBy: "/")
            if parts.count == 2, let n = Double(parts[0]), let d = Double(parts[1]), d > 0 {
                return (n / d, String(t[r.upperBound...]))
            }
        }

        // Plain number "2 " or "2.5 "
        if let r = t.range(of: #"^(\d+(?:\.\d+)?)\s"#, options: .regularExpression) {
            if let n = Double(String(t[r]).trimmingCharacters(in: .whitespaces)) {
                return (n, String(t[r.upperBound...]))
            }
        }

        return (nil, t)
    }

    // MARK: - Step Parsing

    private static func parseSteps(from lines: [String]) -> [String] {
        var steps: [String] = []
        var buffer = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                if !buffer.isEmpty { steps.append(buffer); buffer = "" }
                continue
            }

            let lower = trimmed.lowercased()
            if lower == "cook mode" || lower == "prevent screen from sleeping" { continue }

            // Short sub-headers like "To Cook", "Filling:"
            let wordCount = trimmed.split(separator: " ").count
            if wordCount <= 4 && (trimmed.hasSuffix(":") || trimmed.hasPrefix("To ") || trimmed.hasPrefix("For ")) {
                if !buffer.isEmpty { steps.append(buffer); buffer = "" }
                continue
            }

            // "Step N:" prefix
            if let r = trimmed.range(of: #"^[Ss]tep\s+\d+[.:]\s*"#, options: .regularExpression) {
                if !buffer.isEmpty { steps.append(buffer); buffer = "" }
                buffer = String(trimmed[r.upperBound...])
                continue
            }

            // "1." or "1)" prefix
            if let r = trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                if !buffer.isEmpty { steps.append(buffer); buffer = "" }
                buffer = String(trimmed[r.upperBound...])
                continue
            }

            // Plain line — treat as its own step (most sites put one step per line)
            if buffer.isEmpty {
                buffer = trimmed
            } else {
                buffer += " " + trimmed
            }
        }

        if !buffer.isEmpty { steps.append(buffer) }
        return steps.filter { !$0.isEmpty }
    }

    // MARK: - Utilities

    private static func firstIndex(of keywords: [String], in lines: [String]) -> Int? {
        for (i, line) in lines.enumerated() {
            let lower = line.lowercased().trimmingCharacters(in: .whitespaces)
            if keywords.contains(where: {
                lower == $0 || lower.hasPrefix($0 + " ") || lower.hasPrefix($0 + ":")
            }) {
                return i
            }
        }
        return nil
    }
}
