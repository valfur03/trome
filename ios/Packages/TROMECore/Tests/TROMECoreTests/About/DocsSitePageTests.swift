import Foundation
import Testing
@testable import TROMECore

struct DocsSitePageTests {
    @Test(arguments: [
        (DocsSitePage.privacy, "fr", "https://trome.valfur.fr/fr/privacy/"),
        (DocsSitePage.privacy, "en", "https://trome.valfur.fr/en/privacy/"),
        (DocsSitePage.support, "fr", "https://trome.valfur.fr/fr/support/"),
        (DocsSitePage.support, "en", "https://trome.valfur.fr/en/support/")
    ])
    func eachPageHasTheAddressOfTheStorePage(page: DocsSitePage, language: String, address: String) {
        #expect(page.url(appLanguage: language).absoluteString == address)
    }

    @Test(arguments: ["fr-FR", "fr-CA", "fr_BE"])
    func aFrenchVariantOpensTheFrenchPage(language: String) {
        #expect(DocsSitePage.support.url(appLanguage: language).absoluteString == "https://trome.valfur.fr/fr/support/")
    }

    @Test(arguments: [nil, "", "Base", "de", "en-GB"])
    func anyOtherLanguageOpensTheEnglishPage(language: String?) {
        #expect(DocsSitePage.privacy.url(appLanguage: language).absoluteString == "https://trome.valfur.fr/en/privacy/")
    }
}
