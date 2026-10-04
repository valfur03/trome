import Foundation

enum AboutLinks {
    static let privacyPolicy = placeholder("privacy-policy")
    static let helpAndFeedback = placeholder("help-and-feedback")

    private static func placeholder(_ page: String) -> URL {
        URL(string: "https://example.com/placeholder-\(page)")!
    }
}
