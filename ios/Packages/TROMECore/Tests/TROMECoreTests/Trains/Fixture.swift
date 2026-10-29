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

    /// The examples of one route of the server: `departures`, or `live-activity` (the start of a Live Activity).
    static func apiExampleNames(of route: String) throws -> [String] {
        try apiExampleNames().filter { $0.hasPrefix("\(route)-") }
    }

    static func apiExample(_ name: String) throws -> Data {
        try Data(contentsOf: contractsFolder("api").appending(path: "\(name).json"))
    }

    /// The folders of the recorded sets of promises, one per set of builds in the field.
    static func buildPromiseSetFolders() throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: contractsFolder("builds"), includingPropertiesForKeys: [.isDirectoryKey])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    static func contractsFolder(_ part: String, from file: String = #filePath) throws -> URL {
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
