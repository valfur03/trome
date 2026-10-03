import Foundation
import Testing
@testable import TROMECore

struct TrainServerConfigurationTests {
    private func configuration(host: Any?, token: Any?) -> TrainServerConfiguration? {
        var info: [String: Any] = [:]
        info[TrainServerConfiguration.hostKey] = host
        info[TrainServerConfiguration.appTokenKey] = token
        return TrainServerConfiguration(infoDictionary: info)
    }

    @Test func readsTheHostAndTheAppTokenFromTheInfoDictionary() {
        let server = configuration(host: " trome-server.example.workers.dev\n", token: " abc123 ")

        #expect(server?.baseURL.absoluteString == "https://trome-server.example.workers.dev")
        #expect(server?.appToken == "abc123")
    }

    @Test(arguments: [
        (nil, "abc"),
        ("example.com", nil),
        ("", "abc"),
        ("example.com", "  "),
        ("$(TRAIN_SERVER_HOST)", "abc"),
        ("example.com", "$(TRAIN_SERVER_APP_TOKEN)"),
        ("https://example.com", "abc"),
        ("example.com/v1", "abc"),
        ("example.com:8787", "abc"),
        ("user@example.com", "abc")
    ] as [(String?, String?)])
    func isMissingWithoutAUsableHostAndToken(host: String?, token: String?) {
        #expect(configuration(host: host, token: token) == nil)
    }

    @Test func isMissingWhenASettingIsNotText() {
        #expect(configuration(host: 42, token: "abc") == nil)
        #expect(TrainServerConfiguration(infoDictionary: nil) == nil)
    }
}
