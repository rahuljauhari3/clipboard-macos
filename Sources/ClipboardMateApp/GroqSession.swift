import Foundation

final class GroqSession {
    static let shared = GroqSession()
    private init() {}

    // In-memory only for current app session
    var apiKey: String?
}

