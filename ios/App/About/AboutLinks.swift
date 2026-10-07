import Foundation
import TROMECore

enum AboutLinks {
    static let privacyPolicy = DocsSitePage.privacy.url(appLanguage: appLanguage)
    static let helpAndFeedback = DocsSitePage.support.url(appLanguage: appLanguage)

    private static var appLanguage: String? {
        Bundle.main.preferredLocalizations.first
    }
}
