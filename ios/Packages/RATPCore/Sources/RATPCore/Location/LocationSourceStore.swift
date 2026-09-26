import Foundation

public protocol KeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: KeyValueStore {}

public struct LocationSourceStore {
    public static let key = "testingTools.locationSource"

    private let storage: any KeyValueStore

    public init(storage: any KeyValueStore) {
        self.storage = storage
    }

    public func load() -> LocationSource {
        guard let data = storage.data(forKey: Self.key),
              let source = try? JSONDecoder().decode(LocationSource.self, from: data) else {
            return .realGPS
        }
        return source
    }

    public func save(_ source: LocationSource) {
        storage.set(try? JSONEncoder().encode(source), forKey: Self.key)
    }
}
