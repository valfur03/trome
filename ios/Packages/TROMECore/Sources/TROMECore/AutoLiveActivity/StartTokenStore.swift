import Foundation

/// The last push-to-start token that iOS gave the app, kept on the phone so that a later process can ask with it.
/// It has a key of its own, which no earlier build wrote: a phone updated from such a build opens with no kept token.
/// The token stays on the phone, and goes only in the ask to the server, as the token of this process does.
struct StartTokenStore {
    static let key = "silentStart.startToken"

    private let storage: any KeyValueStore

    init(storage: any KeyValueStore) {
        self.storage = storage
    }

    func load() -> String? {
        storage.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(String.self, from: $0) }
    }

    func save(_ token: String?) {
        storage.set(token.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.key)
    }
}
