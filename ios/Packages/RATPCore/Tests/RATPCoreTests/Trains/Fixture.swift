import Foundation
@testable import RATPCore

enum Fixture {
    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: primFolder().appending(path: "\(name).json"))
    }

    private static func primFolder(from file: String = #filePath) throws -> URL {
        var folder = URL(filePath: file).deletingLastPathComponent()
        while folder.pathComponents.count > 1 {
            let candidate = folder.appending(path: "contracts/prim", directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            folder = folder.deletingLastPathComponent()
        }
        throw FixtureError.noContractsFolder(file)
    }

    static func date(_ text: String) -> Date {
        SIRIDate.parse(text) ?? .distantPast
    }
}

enum FixtureError: Error {
    case noContractsFolder(String)
}
