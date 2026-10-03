import Foundation
@testable import TROMECore

enum Fixture {
    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: contractsFolder("prim").appending(path: "\(name).json"))
    }

    static func apiExampleNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: contractsFolder("api").path())
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
            .sorted()
    }

    static func apiExample(_ name: String) throws -> Data {
        try Data(contentsOf: contractsFolder("api").appending(path: "\(name).json"))
    }

    private static func contractsFolder(_ part: String, from file: String = #filePath) throws -> URL {
        var folder = URL(filePath: file).deletingLastPathComponent()
        while folder.pathComponents.count > 1 {
            let candidate = folder.appending(path: "contracts/\(part)", directoryHint: .isDirectory)
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
