import Foundation
import Testing
@testable import RATPCore

struct TransitLineTests {
    private func json(_ line: TransitLine) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(line), as: UTF8.self)
    }

    @Test func leavesOutTheStopsOfALineThatHasNone() throws {
        #expect(try json(TransitLine(mode: .metro, name: "12")) == #"{"mode":"metro","name":"12"}"#)
    }

    @Test func keepsTheStopsOfALineThatHasThem() throws {
        let line = TransitLine(mode: .metro, name: "12", stopIds: ["IDFM:1"], stopAreaIds: ["IDFM:2"])

        #expect(try json(line) == #"{"mode":"metro","name":"12","stopAreaIds":["IDFM:2"],"stopIds":["IDFM:1"]}"#)
    }

    @Test(arguments: [
        TransitLine(mode: .rer, name: "A"),
        TransitLine(mode: .metro, name: "12", stopIds: ["IDFM:1", "IDFM:2"], stopAreaIds: ["IDFM:3"])
    ])
    func readsBackWhatItWrites(line: TransitLine) throws {
        let data = try JSONEncoder().encode(line)

        #expect(try JSONDecoder().decode(TransitLine.self, from: data) == line)
    }
}
