import Testing
@testable import RATPCore

struct PRIMConfigurationTests {
    @Test func readsTheKeyFromTheInfoDictionary() {
        let configuration = PRIMConfiguration(infoDictionary: ["PRIMAPIKey": "abc123"])

        #expect(configuration?.apiKey == "abc123")
    }

    @Test func trimsSpacesAroundTheKey() {
        let configuration = PRIMConfiguration(infoDictionary: ["PRIMAPIKey": "  abc123\n"])

        #expect(configuration?.apiKey == "abc123")
    }

    @Test(arguments: [
        [:],
        ["PRIMAPIKey": ""],
        ["PRIMAPIKey": "   "],
        ["PRIMAPIKey": "$(PRIM_API_KEY)"],
        ["PRIMAPIKey": 42]
    ] as [[String: any Sendable]])
    func isMissingWhenNoUsableKeyIsSet(infoDictionary: [String: any Sendable]) {
        #expect(PRIMConfiguration(infoDictionary: infoDictionary) == nil)
    }

    @Test func isMissingWithoutAnInfoDictionary() {
        #expect(PRIMConfiguration(infoDictionary: nil) == nil)
    }
}
