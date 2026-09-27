import Foundation
import Testing
@testable import RATPCore

struct StationActivityContentTests {
    private typealias ContentState = StationActivityAttributes.ContentState

    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let line12 = TransitLine(mode: .metro, name: "12", stopIds: ["IDFM:1", "IDFM:2"])
    private let line2 = TransitLine(mode: .metro, name: "2", stopIds: ["IDFM:3", "IDFM:4"])
    private let southQuay = "STIF:StopPoint:Q:1:"
    private let northQuay = "STIF:StopPoint:Q:2:"
    private var station: Station {
        Station(id: "pigalle", name: "Pigalle", coordinate: Coordinate(48.8822, 2.3377), lines: [line12, line2])
    }

    private func time(inMinutes minutes: Double) -> Date {
        now.addingTimeInterval(minutes * 60)
    }

    private func train(
        _ line: TransitLine,
        to destination: String,
        inMinutes minutes: Double,
        from quay: String?
    ) -> Departure {
        Departure(line: line, destination: destination, time: time(inMinutes: minutes), quayRef: quay)
    }

    private func board(_ departures: [Departure], at stations: [Station]? = nil) -> NextTrainsState {
        .departures(DepartureBoard(departures: departures, stations: stations ?? [station], now: now), updatedAt: now)
    }

    private func lines(of content: ContentState) -> [LineTrains] {
        content.trains.linesPage?.lines ?? []
    }

    @Test func keepsTheContentOfTheBiggestHubSmall() throws {
        let catalog = try StationCatalog.bundled()
        let saintLazare = try #require(catalog.stations.first { $0.name == "Saint-Lazare" })
        let hub = catalog.hubStations(of: saintLazare)
        let departures = hub.flatMap(\.lines).map { line in
            Departure(line: line, destination: "Somewhere", time: time(inMinutes: 3), quayRef: nil)
        }

        let content = ContentState(station: saintLazare, trains: board(departures, at: hub), now: now)
        let json = try #require(String(bytes: try JSONEncoder().encode(content), encoding: .utf8))

        #expect(hub.flatMap(\.lines).count >= 9)
        #expect(!json.contains("stopIds"))
        #expect(!json.contains("stopAreaIds"))
        #expect(json.utf8.count < 4_096)
    }

    @Test func showsTheStationName() {
        let content = ContentState(station: station, trains: .loading, now: now)

        #expect(content.stationName == "Pigalle")
        #expect(content.updatedAt == now)
    }

    @Test(arguments: [NextTrainsState.idle, .loading])
    func saysTheTrainsAreLoading(state: NextTrainsState) {
        #expect(ContentState(station: station, trains: state, now: now).trains == .loading)
    }

    @Test(arguments: [
        NextTrainsState.missingKey,
        .noLiveData,
        .failed(.unreachable),
        .failed(.keyRejected),
        .failed(.quotaExceeded),
        .failed(.serviceFailure)
    ])
    func saysThereIsNoDataWhenTheTimesCannotBeFetched(state: NextTrainsState) {
        #expect(ContentState(station: station, trains: state, now: now).trains == .noData)
    }

    @Test func showsEveryLineOfTheStationWithItsDirectionsAndWithoutItsStopIds() {
        let trains = board([
            train(line12, to: "Mairie d'Issy", inMinutes: 3, from: southQuay),
            train(line12, to: "Mairie d'Issy", inMinutes: 9, from: southQuay),
            train(line12, to: "Mairie d'Aubervilliers", inMinutes: 1, from: northQuay),
            train(line2, to: "Nation", inMinutes: 2, from: "STIF:StopPoint:Q:3:")
        ])

        let content = ContentState(station: station, trains: trains, now: now)

        #expect(content.trains == .lines(LinesPage(
            lines: [
                LineTrains(line: TransitLine(mode: .metro, name: "2"), directions: [
                    LineDirection(label: "Porte Dauphine", times: []),
                    LineDirection(label: "Nation", times: [time(inMinutes: 2)])
                ]),
                LineTrains(line: TransitLine(mode: .metro, name: "12"), directions: [
                    LineDirection(label: "Mairie d'Aubervilliers", times: [time(inMinutes: 1)]),
                    LineDirection(label: "Mairie d'Issy", times: [time(inMinutes: 3)])
                ])
            ],
            allLines: [TransitLine(mode: .metro, name: "2"), TransitLine(mode: .metro, name: "12")],
            firstIndex: 0,
            soonestTrain: SoonestTrain(line: TransitLine(mode: .metro, name: "12"), time: time(inMinutes: 1))
        )))
    }

    @Test func keepsALineWithNoUpcomingTrainAndSaysNoTrainsInItsDirections() {
        let trains = board([
            train(line12, to: "Mairie d'Issy", inMinutes: -0.25, from: southQuay),
            train(line2, to: "Nation", inMinutes: 2, from: "STIF:StopPoint:Q:3:")
        ])

        let content = ContentState(station: station, trains: trains, now: now)

        #expect(lines(of: content).map(\.line.name) == ["2", "12"])
        #expect(lines(of: content)[1].directions == [
            LineDirection(label: "Mairie d'Aubervilliers", times: []),
            LineDirection(label: "Mairie d'Issy", times: [])
        ])
    }

    @Test func showsBothDirectionsWithTwoTrainsEachAtAStationWithOneLine() {
        let abbesses = Station(
            id: "abbesses",
            name: "Abbesses",
            coordinate: Coordinate(48.8844, 2.3384),
            lines: [line12]
        )
        let trains = board([
            train(line12, to: "Mairie d'Issy", inMinutes: 3, from: southQuay),
            train(line12, to: "Mairie d'Issy", inMinutes: 9, from: southQuay),
            train(line12, to: "Mairie d'Aubervilliers", inMinutes: 1, from: northQuay)
        ], at: [abbesses])

        let content = ContentState(station: abbesses, trains: trains, now: now)

        #expect(content.trains.linesPage?.allLines == [TransitLine(mode: .metro, name: "12")])
        #expect(lines(of: content).flatMap(\.directions) == [
            LineDirection(label: "Mairie d'Aubervilliers", times: [time(inMinutes: 1)]),
            LineDirection(label: "Mairie d'Issy", times: [time(inMinutes: 3), time(inMinutes: 9)])
        ])
    }

    @Test func showsTheLinesOfEveryStationOfTheHubEachWithTheStationThatServesIt() {
        let mairieDIssy = Station(
            id: "mairie-d-issy",
            name: "Mairie d'Issy",
            coordinate: Coordinate(48.8243, 2.2735),
            lines: [line12]
        )
        let lineTwoOnly = Station(
            id: "pigalle",
            name: "Pigalle",
            coordinate: Coordinate(48.8822, 2.3377),
            lines: [line2]
        )
        let trains = board([
            train(line12, to: "Mairie d'Aubervilliers", inMinutes: 4, from: northQuay),
            train(line2, to: "Nation", inMinutes: 2, from: "STIF:StopPoint:Q:3:")
        ], at: [lineTwoOnly, mairieDIssy])

        let content = ContentState(station: lineTwoOnly, trains: trains, now: now)

        #expect(content.stationName == "Pigalle")
        #expect(lines(of: content).map(\.line.name) == ["2", "12"])
        #expect(lines(of: content)[1].directions == [
            LineDirection(label: "Mairie d'Aubervilliers", times: [time(inMinutes: 4)])
        ])
    }

    @Test func startsThePageAtTheAskedLine() {
        let trains = board([train(line2, to: "Nation", inMinutes: 2, from: "STIF:StopPoint:Q:3:")])

        let content = ContentState(station: station, trains: trains, now: now, firstLineIndex: 1)

        #expect(content.trains.linesPage?.firstIndex == 1)
        #expect(lines(of: content).map(\.line.name) == ["12"])
    }

    @Test func saysThereIsNoDataWhenNoLineHasADirection() {
        let unknownLine = TransitLine(mode: .metro, name: "99", stopIds: ["IDFM:9"])
        let unknown = Station(id: "unknown", name: "Unknown", coordinate: Coordinate(48.87, 2.33), lines: [unknownLine])

        let content = ContentState(station: unknown, trains: board([], at: [unknown]), now: now)

        #expect(content.trains == .noData)
    }

    @Test func dropsTimesMoreThanAnHourAwayAndSaysNoTrainsForADirectionLeftEmpty() {
        let trains = board([
            train(line12, to: "Mairie d'Issy", inMinutes: 154, from: southQuay),
            train(line12, to: "Mairie d'Issy", inMinutes: 8, from: southQuay),
            train(line12, to: "Mairie d'Aubervilliers", inMinutes: 75, from: northQuay)
        ])

        #expect(lines(of: ContentState(station: station, trains: trains, now: now))[1].directions == [
            LineDirection(label: "Mairie d'Aubervilliers", times: []),
            LineDirection(label: "Mairie d'Issy", times: [time(inMinutes: 8)])
        ])
    }

    @Test func becomesStaleWhenTheSoonestTrainOfAnyLineLeaves() {
        let trains = board([
            train(line12, to: "Mairie d'Issy", inMinutes: 3, from: southQuay),
            train(line2, to: "Nation", inMinutes: 2, from: "STIF:StopPoint:Q:3:")
        ])

        let content = ContentState(station: station, trains: trains, now: now, firstLineIndex: 1)

        #expect(lines(of: content).map(\.line.name) == ["12"])
        #expect(content.staleDate == time(inMinutes: 2))
    }

    @Test func neverBecomesStaleWhenNoDirectionHasATrain() {
        let trains = board([train(line12, to: "Mairie d'Issy", inMinutes: -0.25, from: southQuay)])

        #expect(ContentState(station: station, trains: trains, now: now).staleDate == nil)
    }

    @Test func becomesStaleWhenTheTrainsTakeTooLongToLoad() {
        let content = ContentState(station: station, trains: .loading, now: now)

        #expect(content.staleDate == now.addingTimeInterval(ContentState.loadingTimeout))
    }

    @Test func neverBecomesStaleWithoutTrainTimes() {
        #expect(ContentState(station: station, trains: .noLiveData, now: now).staleDate == nil)
    }
}
