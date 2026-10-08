import Foundation
import Testing
@testable import TROMECore

struct StationActivityContentServerOutTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let line12 = TransitLine(mode: .metro, name: "12")

    private func lines(isOut: Bool) -> StationActivityAttributes.ContentState {
        let train = LineDirection.Train(time: now.addingTimeInterval(120), destination: "Mairie d'Issy")
        let page = LinesPage(
            showing: [LineTrains(line: line12, directions: [LineDirection(label: "Mairie d'Issy", trains: [train])])],
            from: 0
        )
        return .init(stationName: "Concorde", trains: .lines(page), updatedAt: now, serverIsOut: isOut)
    }

    @Test func readsTheContentOfAnOlderAppAsNotOut() throws {
        let older = #"{"stationName":"Concorde","trains":{"noData":{}},"updatedAt":0}"#

        let content = try JSONDecoder().decode(StationActivityAttributes.ContentState.self, from: Data(older.utf8))

        #expect(content.serverIsOut == false)
        #expect(content.isMarkedStale == false)
        #expect(content.trains == .noData)
    }

    @Test(arguments: [(false, false, false), (true, false, true), (false, true, true), (true, true, true)])
    func looksStaleWhenIOSSaysSoOrTheAppMarkedIt(systemSaysStale: Bool, isMarkedStale: Bool, looksStale: Bool) {
        var content = lines(isOut: true)
        content.isMarkedStale = isMarkedStale

        #expect(content.isStale(systemSaysStale: systemSaysStale) == looksStale)
    }

    @Test func keepsWhetherTheServerIsOutFromTheAppToTheWidget() throws {
        var content = lines(isOut: true)
        content.isMarkedStale = true

        let data = try JSONEncoder().encode(content)

        #expect(try JSONDecoder().decode(StationActivityAttributes.ContentState.self, from: data) == content)
    }

    @Test func saysTheServerIsOutForTheTrainsOfAnOutAnswer() {
        let station = Station(id: "c", name: "Concorde", coordinate: Coordinate(48.8656, 2.3212), lines: [line12])

        let content = StationActivityAttributes.ContentState(
            station: station,
            trains: .failed(.serverOut(retryAt: now.addingTimeInterval(1_840))),
            now: now
        )

        #expect(content.trains == .noData)
        #expect(content.serverIsOut)
    }

    @Test func saysTimesAreUnavailableInTheIslandOnceTheKeptTimesAreStale() {
        #expect(lines(isOut: true).dynamicIslandWait(isStale: true).wait == .timesUnavailable)
        #expect(lines(isOut: false).dynamicIslandWait(isStale: true).wait == .stale)
    }

    @Test func keepsCountingDownInTheIslandUntilTheKeptTimesAreStale() {
        let counting = lines(isOut: false).dynamicIslandWait(isStale: false)

        #expect(lines(isOut: true).dynamicIslandWait(isStale: false) == counting)
    }

    @Test func saysTimesAreUnavailableInTheIslandInsteadOfNoData() {
        let content = StationActivityAttributes.ContentState(
            stationName: "Concorde", trains: .noData, updatedAt: now, serverIsOut: true
        )

        #expect(content.dynamicIslandWait(isStale: false).wait == .timesUnavailable)
        #expect(content.dynamicIslandWait(isStale: false).minimalWait == .dash)
    }
}
