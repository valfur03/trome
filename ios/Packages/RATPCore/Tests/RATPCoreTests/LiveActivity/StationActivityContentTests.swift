import Foundation
import Testing
@testable import RATPCore

struct StationActivityContentTests {
    typealias ContentState = StationActivityAttributes.ContentState

    let now = Date(timeIntervalSince1970: 1_000_000)
    let line12 = TransitLine(mode: .metro, name: "12", stopIds: ["IDFM:1", "IDFM:2"])
    let line2 = TransitLine(mode: .metro, name: "2", stopIds: ["IDFM:3", "IDFM:4"])
    let southQuay = "STIF:StopPoint:Q:1:"
    let northQuay = "STIF:StopPoint:Q:2:"
    var station: Station {
        Station(id: "pigalle", name: "Pigalle", coordinate: Coordinate(48.8822, 2.3377), lines: [line12, line2])
    }
    private var abbesses: Station {
        Station(id: "abbesses", name: "Abbesses", coordinate: Coordinate(48.8844, 2.3384), lines: [line12])
    }

    func time(inMinutes minutes: Double) -> Date {
        now.addingTimeInterval(minutes * 60)
    }

    func train(
        _ line: TransitLine,
        to destination: String,
        inMinutes minutes: Double,
        from quay: String?
    ) -> Departure {
        Departure(line: line, destination: destination, time: time(inMinutes: minutes), quayRef: quay)
    }

    func board(_ departures: [Departure], at stations: [Station]? = nil) -> NextTrainsState {
        .departures(DepartureBoard(departures: departures, stations: stations ?? [station], now: now), updatedAt: now)
    }

    func lines(of content: ContentState) -> [LineTrains] {
        content.trains.linesPage?.lines ?? []
    }

    func linesOfEveryPage(at station: Station, trains: NextTrainsState) -> [LineTrains] {
        var shown: [LineTrains] = []
        var index = 0
        repeat {
            let content = ContentState(station: station, trains: trains, now: now, firstLineIndex: index)
            guard let page = content.trains.linesPage else { break }
            shown += page.lines
            index = page.nextFirstIndex
        } while index != 0 && shown.count <= 20
        return shown
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
                ])
            ],
            allLines: [TransitLine(mode: .metro, name: "2"), TransitLine(mode: .metro, name: "12")],
            firstIndex: 0,
            soonestTrain: SoonestTrain(line: TransitLine(mode: .metro, name: "12"), time: time(inMinutes: 1))
        )))
        #expect(linesOfEveryPage(at: station, trains: trains).last == LineTrains(
            line: TransitLine(mode: .metro, name: "12"),
            directions: [
                LineDirection(label: "Mairie d'Aubervilliers", times: [time(inMinutes: 1)]),
                LineDirection(label: "Mairie d'Issy", times: [time(inMinutes: 3), time(inMinutes: 9)])
            ]
        ))
    }

    @Test func keepsALineWithNoUpcomingTrainAndSaysNoTrainsInItsDirections() {
        let trains = board([
            train(line12, to: "Mairie d'Issy", inMinutes: -0.25, from: southQuay),
            train(line2, to: "Nation", inMinutes: 2, from: "STIF:StopPoint:Q:3:")
        ])

        let shown = linesOfEveryPage(at: station, trains: trains)

        #expect(shown.map(\.line.name) == ["2", "12"])
        #expect(shown[1].directions == [
            LineDirection(label: "Mairie d'Aubervilliers", times: []),
            LineDirection(label: "Mairie d'Issy", times: [])
        ])
    }

    @Test func showsBothDirectionsWithTwoTrainsEachAtAStationWithOneLine() {
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

    @Test func keepsOnlyTheNextTrainOfEachDirectionForTheDynamicIsland() {
        let trains = board([
            train(line12, to: "Mairie d'Issy", inMinutes: 3, from: southQuay),
            train(line12, to: "Mairie d'Issy", inMinutes: 9, from: southQuay),
            train(line12, to: "Mairie d'Aubervilliers", inMinutes: 1, from: northQuay),
            train(line12, to: "Mairie d'Aubervilliers", inMinutes: 7, from: northQuay)
        ], at: [abbesses])
        let content = ContentState(station: abbesses, trains: trains, now: now)

        let island = content.keepingOnlyTheNextTrains

        #expect(lines(of: content).flatMap(\.directions).map(\.trains.count) == [2, 2])
        #expect(island.stationName == "Abbesses")
        #expect(island.updatedAt == content.updatedAt)
        #expect(lines(of: island).flatMap(\.directions) == [
            LineDirection(label: "Mairie d'Aubervilliers", times: [time(inMinutes: 1)]),
            LineDirection(label: "Mairie d'Issy", times: [time(inMinutes: 3)])
        ])
    }

    @Test(arguments: [NextTrainsState.loading, .noLiveData])
    func keepsTheContentWithoutTrainsForTheDynamicIsland(trains: NextTrainsState) {
        let content = ContentState(station: station, trains: trains, now: now)

        #expect(content.keepingOnlyTheNextTrains == content)
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
        let shown = linesOfEveryPage(at: lineTwoOnly, trains: trains)

        #expect(content.stationName == "Pigalle")
        #expect(shown.map(\.line.name) == ["2", "12"])
        #expect(shown.map(\.stationName) == [nil, "Mairie d'Issy"])
        #expect(shown[1].directions == [
            LineDirection(label: "Mairie d'Aubervilliers", times: [time(inMinutes: 4)])
        ])
    }

    @Test func showsTheLinesOfTheHeaderStationOnTheFirstPageOfAHub() throws {
        let catalog = try StationCatalog.bundled()
        let station = try #require(catalog.stations.first { $0.name == "Châtelet - Les Halles" })
        let hub = catalog.hubStations(of: station)

        let content = ContentState(station: station, trains: board([], at: hub), now: now)
        let page = try #require(content.trains.linesPage)

        #expect(page.allLines.map(\.name) == ["A", "B", "D", "4", "1", "7", "11", "14"])
        #expect(!page.lines.isEmpty)
        #expect(page.lines.allSatisfy { $0.line.mode == .rer && $0.stationName == nil })
    }

    @Test func startsThePageAtTheAskedLine() {
        let trains = board([train(line2, to: "Nation", inMinutes: 2, from: "STIF:StopPoint:Q:3:")])

        let content = ContentState(station: station, trains: trains, now: now, firstLineIndex: 1)

        #expect(content.trains.linesPage?.firstIndex == 1)
        #expect(lines(of: content).map(\.line.name) == ["12"])
    }

    @Test func showsEveryLineWithoutTrainsWhenNoLineHasADirection() {
        let trains = board([train(line12, to: "Mairie d'Issy", inMinutes: -0.25, from: southQuay)])

        #expect(linesOfEveryPage(at: station, trains: trains) == [
            LineTrains(line: TransitLine(mode: .metro, name: "2"), directions: [
                LineDirection(label: "Porte Dauphine", times: []),
                LineDirection(label: "Nation", times: [])
            ]),
            LineTrains(line: TransitLine(mode: .metro, name: "12"), directions: [
                LineDirection(label: "Mairie d'Aubervilliers", times: []),
                LineDirection(label: "Mairie d'Issy", times: [])
            ])
        ])
    }

    @Test func showsEveryLineOfTheStationWithoutTrainsWhenPRIMHasNoTrain() {
        #expect(linesOfEveryPage(at: station, trains: .noLiveData) == [
            LineTrains(line: TransitLine(mode: .metro, name: "2"), directions: []),
            LineTrains(line: TransitLine(mode: .metro, name: "12"), directions: [])
        ])
    }

    @Test func keepsTheColorOfEachLine() {
        let color = LineColor(background: "00643c", text: "ffffff")
        var colored = line12
        colored.color = color
        let abbesses = Station(
            id: "abbesses",
            name: "Abbesses",
            coordinate: Coordinate(48.8844, 2.3384),
            lines: [colored]
        )
        let trains = board([train(colored, to: "Mairie d'Issy", inMinutes: 3, from: southQuay)], at: [abbesses])

        let content = ContentState(station: abbesses, trains: trains, now: now)

        #expect(content.trains.linesPage?.allLines.map(\.color) == [color])
        #expect(lines(of: content).map(\.line.color) == [color])
    }

    @Test func staysUnderTheSizeLimitOfALiveActivityAtTheBiggestHub() throws {
        let catalog = try StationCatalog.bundled()
        let chatelet = try #require(catalog.stations(matching: "Châtelet").first { $0.name == "Châtelet" })
        let stations = catalog.hubStations(of: chatelet)
        let departures = stations.flatMap(\.lines).flatMap { line in
            (0..<8).map { index in
                Departure(
                    line: line,
                    destination: "A very long destination name number \(index % 2)",
                    time: time(inMinutes: 0.5 + Double(index)),
                    arrivalTime: time(inMinutes: Double(index)),
                    isAtStop: index == 0
                )
            }
        }
        let trains = NextTrainsState.departures(
            DepartureBoard(departures: departures, stations: stations, now: now),
            updatedAt: now
        )

        let content = ContentState(station: chatelet, trains: trains, now: now)

        #expect(content.trains.linesPage?.allLines.count ?? 0 >= 8)
        #expect(try JSONEncoder().encode(content).count < 4096)
    }
}
