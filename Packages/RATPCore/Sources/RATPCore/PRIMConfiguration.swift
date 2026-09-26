import Foundation

public struct PRIMConfiguration: Equatable, Sendable {
    public static let infoDictionaryKey = "PRIMAPIKey"

    public let apiKey: String

    public init?(infoDictionary: [String: Any]?) {
        guard let rawValue = infoDictionary?[Self.infoDictionaryKey] as? String else {
            return nil
        }
        let apiKey = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty, !apiKey.hasPrefix("$(") else {
            return nil
        }
        self.apiKey = apiKey
    }
}
