import Testing
@testable import TROMECore

struct PRIMStopReferenceTests {
    @Test func asksForAMetroStopByItsQuay() {
        #expect(PRIMStopReference.monitoringRef(forStopId: "IDFM:463116") == "STIF:StopPoint:Q:463116:")
    }

    @Test func asksForAnRERStopByItsStopArea() {
        #expect(
            PRIMStopReference.monitoringRef(forStopId: "IDFM:monomodalStopPlace:45102") == "STIF:StopArea:SP:45102:"
        )
    }

    @Test(arguments: ["", "IDFM:", "IDFM:monomodalStopPlace:", "IDFM:other:12", "STIF:123"])
    func ignoresUnknownStopIds(stopId: String) {
        #expect(PRIMStopReference.monitoringRef(forStopId: stopId) == nil)
    }

    @Test func readsTheLineCodeFromALineRef() {
        #expect(PRIMStopReference.lineCode(fromLineRef: "STIF:Line::C01382:") == "C01382")
    }

    @Test func knowsTheCodeOfEveryLineInTheStationList() throws {
        let lines = Set(try StationCatalog.bundled().stations.flatMap(\.lines).map {
            TransitLine(mode: $0.mode, name: $0.name)
        })

        #expect(lines.count == 21)
        #expect(lines.filter { $0.primLineCode == nil }.isEmpty)
        #expect(Set(lines.compactMap(\.primLineCode)).count == lines.count)
    }
}
