import Foundation

public enum DocsSitePage: String, Sendable {
    case privacy
    case support

    static let site = URL(string: "https://trome.valfur.fr/")!

    public func url(appLanguage: String?) -> URL {
        let language = Locale.Language(identifier: appLanguage ?? "").languageCode == .french ? "fr" : "en"
        return Self.site.appending(path: "\(language)/\(rawValue)/", directoryHint: .isDirectory)
    }
}
