import Foundation

public struct TrainServerConfiguration: Equatable, Sendable {
    public static let hostKey = "TrainServerHost"
    public static let appTokenKey = "TrainServerAppToken"

    public let baseURL: URL
    public let appToken: String

    public init?(infoDictionary: [String: Any]?) {
        guard let host = Self.setting(Self.hostKey, in: infoDictionary),
              let appToken = Self.setting(Self.appTokenKey, in: infoDictionary)
        else {
            return nil
        }
        guard let baseURL = URL(string: "https://\(host)"), baseURL.host() == host, baseURL.path().isEmpty else {
            return nil
        }
        self.baseURL = baseURL
        self.appToken = appToken
    }

    private static func setting(_ key: String, in infoDictionary: [String: Any]?) -> String? {
        guard let rawValue = infoDictionary?[key] as? String else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }
}
