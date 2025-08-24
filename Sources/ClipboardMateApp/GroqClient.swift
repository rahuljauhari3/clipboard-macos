import Foundation
import AppKit

struct GroqModel: Identifiable, Hashable, Decodable {
    let id: String
    let created: Int?
    let ownedBy: String?

    // Heuristic flags parsed from metadata if available
    let supportsWebSearch: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case created
        case ownedBy = "owned_by"
    }

    init(id: String, created: Int? = nil, ownedBy: String? = nil, supportsWebSearch: Bool = false) {
        self.id = id
        self.created = created
        self.ownedBy = ownedBy
        self.supportsWebSearch = supportsWebSearch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.created = try? container.decode(Int.self, forKey: .created)
        self.ownedBy = try? container.decode(String.self, forKey: .ownedBy)
        // Default false; we'll override in GroqClient based on server-provided metadata if any
        self.supportsWebSearch = false
    }
}

struct GroqChatMessage: Codable {
    enum Role: String, Codable { case system, user, assistant }
    let role: Role
    let content: String
}

final class GroqClient {
    static let shared = GroqClient()

    // OpenAI-compatible base URL on Groq
    var baseURL: URL = URL(string: "https://api.groq.com/openai/v1")!

    // Known models with web search capability (fallback if API does not expose this)
    private let knownWebSearchModels: Set<String> = [
        // Add/adjust as Groq updates; placeholder examples
        "llama-3.3-70b-versatile",
        "llama-3.3-8b-instant"
    ]

    private var urlSession: URLSession = .shared

    private func apiKey() throws -> String {
        if let key = KeychainService.shared.get(key: .groqAPIKey), !key.isEmpty {
            return key
        }
        throw NSError(domain: "GroqClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Groq API key. Set it in Preferences."])
    }

    func fetchModels() async throws -> [GroqModel] {
        let key = try apiKey()
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "GroqClient", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch models: \(body)"])
        }

        // OpenAI-compatible format: { data: [ {id: "...", ...}, ... ] }
        struct ModelsEnvelope: Decodable { let data: [ModelItem] }
        struct ModelItem: Decodable { let id: String }

        let env = try JSONDecoder().decode(ModelsEnvelope.self, from: data)
        let models = env.data.map { GroqModel(id: $0.id, supportsWebSearch: knownWebSearchModels.contains($0.id)) }
        return models
    }

    func chat(messages: [GroqChatMessage], model: String, useWebSearch: Bool) async throws -> String {
        let key = try apiKey()
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build body
        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { [
                "role": $0.role.rawValue,
                "content": $0.content
            ] },
            "stream": false
        ]
        if useWebSearch {
            // Groq docs indicate built-in Web Search tool; use OpenAI tool syntax
            body["tools"] = [["type": "web_search"]]
            body["tool_choice"] = "auto"
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "GroqClient", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "Chat request failed: \(bodyStr)"])
        }

        struct Choice: Decodable { struct Message: Decodable { let role: String; let content: String? }; let message: Message }
        struct ChatResponse: Decodable { let choices: [Choice] }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let content = decoded.choices.first?.message.content ?? ""
        return content
    }
}

