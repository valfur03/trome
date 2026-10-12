import Foundation
import Testing
@testable import TROMECore

struct DynamicIslandWaitTests {
    typealias ContentState = StationActivityAttributes.ContentState

    let now = Date(timeIntervalSince1970: 1_000_000)
    let line13 = TransitLine(mode: .metro, name: "13")
    let line14 = TransitLine(mode: .metro, name: "14")

    private func time(inSeconds seconds: TimeInterval) -> Date {
        now.addingTimeInterval(seconds)
    }

    private func content(_ lines: [LineTrains], laterTrain: Departure? = nil) -> ContentState {
        ContentState(
            stationName: "Station",
            trains: .lines(LinesPage(showing: lines, from: 0, laterTrain: laterTrain)),
            updatedAt: now
        )
    }

    private func content(at stationName: String, recordedIn fixture: String, now: Date) throws -> ContentState {
        let catalog = try StationCatalog.bundled()
        let station = try #require(catalog.stations.first { $0.name == stationName })
        let visits = try StopMonitoringResponse.visits(from: Fixture.data(fixture))
        let departures = PRIMDeparturesProvider.departures(from: visits, at: [station])
        let board = DepartureBoard(departures: departures, stations: [station], now: now)
        return ContentState(station: station, trains: .departures(board, updatedAt: now), now: now)
    }

    private func abbesses(at now: Date) throws -> DynamicIslandWait {
        try content(at: "Abbesses", recordedIn: "stop-monitoring-abbesses-stop-area", now: now)
            .dynamicIslandWait(isStale: false)
    }

    private func direction(
        _ label: String,
        _ trains: [LineDirection.Train],
        branchEnds: [String]? = nil
    ) -> LineDirection {
        LineDirection(label: label, trains: trains, branchEnds: branchEnds)
    }

    private func train(
        inSeconds seconds: TimeInterval,
        to destination: String = "End",
        status: PlatformStatus? = nil
    ) -> LineDirection.Train {
        LineDirection.Train(time: time(inSeconds: seconds), destination: destination, status: status)
    }

    @Test func showsTheLineAndTheMinutesOfTheNextTrainAtAStationWithOneLineFromARecordedAnswer() throws {
        let recordedAt = Fixture.date("2026-09-26T10:00:00Z")

        let island = try abbesses(at: recordedAt)

        #expect(island.line?.name == "12")
        guard case .minutes(let train, let mode) = island.wait else {
            Issue.record("Expected minutes, got \(island.wait)")
            return
        }
        #expect(train.time == Fixture.date("2026-09-26T10:02:30Z"))
        #expect(mode == .metro)
        #expect(train.countdownMinutes(at: recordedAt, on: mode) == 2)
    }

    @Test func readsZeroWhenTheNextTrainIsApproachingThenAtThePlatformFromARecordedAnswer() throws {
        let approachingAt = Fixture.date("2026-09-26T10:01:20Z")
        let atPlatformAt = Fixture.date("2026-09-26T10:02:15Z")

        let approaching = try abbesses(at: approachingAt)
        let atPlatform = try abbesses(at: atPlatformAt)

        #expect(approaching.wait == .approaching)
        #expect(approaching.minimalWait == .zero)
        #expect(atPlatform.wait == .atPlatform)
        #expect(atPlatform.minimalWait == .zero)
        #expect(atPlatform.line?.name == "12")
    }

    @Test func leadsWithTheLineOfTheSoonestTrainAtAHubFromARecordedAnswer() throws {
        let recordedAt = Fixture.date("2026-09-27T08:00:00Z")

        let island = try content(
            at: "Châtelet - Les Halles",
            recordedIn: "stop-monitoring-chatelet-rer",
            now: recordedAt
        )
            .dynamicIslandWait(isStale: false)

        #expect(island.line?.mode == .rer)
        #expect(island.line?.name == "A")
        guard case .minutes(let train, let mode) = island.wait else {
            Issue.record("Expected minutes, got \(island.wait)")
            return
        }
        #expect(train.time == Fixture.date("2026-09-27T08:02:00Z"))
        #expect(mode == .rer)
    }

    @Test func leadsWithTheLineWhoseTrainComesFirstAlsoWhenItIsNotTheFirstLineOrOnThePage() {
        let lines = [
            LineTrains(line: line13, directions: [direction("Châtillon", [train(inSeconds: 400)])]),
            LineTrains(line: line14, directions: [direction("Olympiades", [train(inSeconds: 100)])])
        ]

        let island = content(lines).dynamicIslandWait(isStale: false)

        #expect(island.line == line14)
        #expect(island.wait == .minutes(train(inSeconds: 100), .metro))
    }

    @Test func leadsWithAnotherLineByItselfWhenTheSoonestTrainHasLeft() {
        let before = [
            LineTrains(line: line13, directions: [
                direction("Châtillon", [train(inSeconds: 30), train(inSeconds: 400)])
            ]),
            LineTrains(line: line14, directions: [direction("Olympiades", [train(inSeconds: 100)])])
        ]
        let after = [
            LineTrains(line: line13, directions: [direction("Châtillon", [train(inSeconds: 400)])]),
            LineTrains(line: line14, directions: [direction("Olympiades", [train(inSeconds: 100)])])
        ]

        #expect(content(before).dynamicIslandWait(isStale: false).line == line13)
        #expect(content(after).dynamicIslandWait(isStale: false).line == line14)
    }

    @Test func leadsWithTheLineAndTheMinutesOfTheSoonestTrainOfAForkWithNoMarkOfItsEnd() {
        let ends = ["Saint-Denis Université", "Les Courtilles"]
        let fork = LineTrains(line: line13, directions: [
            direction("Châtillon - Montrouge", [train(inSeconds: 300, to: "Châtillon - Montrouge")]),
            direction(ends.joined(separator: " / "), [
                train(inSeconds: 120, to: "Les Courtilles"),
                train(inSeconds: 360, to: "Saint-Denis Université")
            ], branchEnds: ends)
        ])

        let island = content([fork]).dynamicIslandWait(isStale: false)

        let wait = DynamicIslandWait.Wait.minutes(train(inSeconds: 120, to: "Les Courtilles"), .metro)
        #expect(island == DynamicIslandWait(line: line13, wait: wait))
    }

    @Test func readsTheSoonestTrainOfALiveActivityWhoseOlderAppSentTheMarkOfItsEnd() throws {
        let page = LinesPage(
            lines: [],
            allLines: [line13],
            firstIndex: 0,
            soonestTrain: SoonestTrain(line: line13, train: train(inSeconds: 120, to: "Les Courtilles"))
        )
        var json = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(page)) as? [String: Any]
        )
        var soonest = try #require(json["soonestTrain"] as? [String: Any])
        soonest["branchEndIndex"] = 1
        json["soonestTrain"] = soonest

        let decoded = try JSONDecoder().decode(LinesPage.self, from: JSONSerialization.data(withJSONObject: json))

        #expect(decoded.soonestTrain == page.soonestTrain)
    }

    @Test func saysNoTrainWithTheFirstLineWhenNoLineHasATrain() {
        let lines = [
            LineTrains(line: line13, directions: [direction("Châtillon", [])]),
            LineTrains(line: line14, directions: [direction("Olympiades", [])])
        ]

        let island = content(lines).dynamicIslandWait(isStale: false)

        #expect(island.line == line13)
        #expect(island.wait == .noTrain)
        #expect(island.minimalWait == .dash)
    }

    @Test func saysOverAnHourWithTheLineOfTheFirstLaterTrain() {
        let lines = [
            LineTrains(line: line13, directions: [
                LineDirection(label: "Châtillon", trains: [], nextTrainIsOverAnHourAway: true)
            ]),
            LineTrains(line: line14, directions: [
                LineDirection(label: "Olympiades", trains: [], nextTrainIsOverAnHourAway: true)
            ])
        ]
        let laterTrain = Departure(line: line14, destination: "Olympiades", time: time(inSeconds: 3_900))

        let island = content(lines, laterTrain: laterTrain).dynamicIslandWait(isStale: false)

        #expect(island.line == line14)
        #expect(island.wait == .overAnHour)
        #expect(island.minimalWait == .dash)
    }

    @Test func showsNoNumberWhenStaleButKeepsTheLine() {
        let lines = [LineTrains(line: line13, directions: [direction("Châtillon", [train(inSeconds: 100)])])]
        let laterLines = [LineTrains(line: line13, directions: [
            LineDirection(label: "Châtillon", trains: [], nextTrainIsOverAnHourAway: true)
        ])]

        let stale = content(lines).dynamicIslandWait(isStale: true)

        #expect(stale.line == line13)
        #expect(stale.wait == .stale)
        #expect(stale.minimalWait == .dash)
        #expect(content(laterLines).dynamicIslandWait(isStale: true).wait == .stale)
    }

    @Test func showsNoLineAndNoNumberWhileLoadingOrWithoutData() {
        let loading = ContentState(stationName: "Station", trains: .loading, updatedAt: now)
        let noData = ContentState(stationName: "Station", trains: .noData, updatedAt: now)

        #expect(loading.dynamicIslandWait(isStale: false) == DynamicIslandWait(line: nil, wait: .loading))
        #expect(loading.dynamicIslandWait(isStale: true).wait == .stale)
        #expect(noData.dynamicIslandWait(isStale: false) == DynamicIslandWait(line: nil, wait: .noData))
        #expect(loading.dynamicIslandWait(isStale: false).minimalWait == .dash)
    }

    @Test func keepsShowingTheMinutesOfALiveActivityMadeByAnOlderApp() {
        let page = LinesPage(
            lines: [LineTrains(line: line13, directions: [])],
            allLines: [line13],
            firstIndex: 0,
            soonestTrain: SoonestTrain(line: line13, time: time(inSeconds: 200))
        )
        let older = ContentState(stationName: "Station", trains: .lines(page), updatedAt: now)

        guard case .minutes(let train, _) = older.dynamicIslandWait(isStale: false).wait else {
            Issue.record("Expected minutes")
            return
        }
        #expect(train.time == time(inSeconds: 200))
    }

    @Test func showsTheMinutesInTheMinimalViewToo() {
        let lines = [LineTrains(line: line13, directions: [direction("Châtillon", [train(inSeconds: 100)])])]

        #expect(content(lines).dynamicIslandWait(isStale: false).minimalWait == .minutes(train(inSeconds: 100), .metro))
    }
}
