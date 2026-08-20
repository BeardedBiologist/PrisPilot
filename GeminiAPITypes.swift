import Foundation

// MARK: - Response Types (Decodable only — request is built as [String: Any])

struct GeminiResponse: Decodable {
    let candidates: [GeminiCandidate]?
    let error: GeminiAPIError?
}

struct GeminiCandidate: Decodable {
    let content: GeminiResponseContent?
    let finishReason: String?
}

struct GeminiResponseContent: Decodable {
    let role: String?
    let parts: [GeminiResponsePart]
}

struct GeminiResponsePart: Decodable {
    let text: String?
    let functionCall: GeminiFunctionCallResult?
}

struct GeminiFunctionCallResult: Decodable {
    let name: String
    let args: [String: GeminiArgValue]?
}

struct GeminiAPIError: Decodable {
    let code: Int?
    let message: String
    let status: String?
}

// MARK: - Argument Value (handles string, number, bool in function call args)

enum GeminiArgValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self)   { self = .bool(v);   return }
        if let v = try? c.decode(Double.self)  { self = .number(v); return }
        if let v = try? c.decode(String.self)  { self = .string(v); return }
        self = .null
    }

    var stringValue: String?  { if case .string(let v) = self { return v }; return nil }
    var doubleValue: Double?  { if case .number(let v) = self { return v }; return nil }
    var boolValue:   Bool?    { if case .bool(let v)   = self { return v }; return nil }
}
