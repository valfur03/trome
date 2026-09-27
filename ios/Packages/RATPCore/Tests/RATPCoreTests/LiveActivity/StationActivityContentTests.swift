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

    private func board(_ departures: [Departure]) -> NextTrainsState {
        .departures(DepartureBoard(departures: departures, lines: station.lines, now: now), updatedAt: now)
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

    @Test func showsBothDirectionsOfTheFirstLineWithoutItsStopIds() {
        let trains = board([
            train(line12, to: "Mairie d'Issy", inMinutes: 3, from: southQuay),
            train(line12, to: "Mairie d'Issy", inMinutes: 9, from: southQuay),
            train(line12, to: "Mairie d'Aubervilliers", inMinutes: 1, from: northQuay),
            train(line2, to: "Nation", inMinutes: 2, from: "STIF:StopPoint:Q:3:")
        ])

        let content = ContentState(station: station, trains: trains, now: now)

        #expect(content.trains == .directions(line: TransitLine(mode: .metro, name: "12"), [
            LineDirection(label: "Mairie d'Aubervilliers", times: [time(inMinutes: 1)]),
            LineDirection(label: "Mairie d'Issy", times: [time(inMinutes: 3), time(inMinutes: 9)])
        ]))
    }

    @Test func showsTheNextLineWhenTheFirstLineHasNoUpcomingTrain() {
        let trains = board([
            train(line12, to: "Mairie d'Issy", inMinutes: -0.25, from: southQuay),
            train(line2, to: "Nation", inMinutes: 2, from: "STIF:StopPoint:Q:3:")
        ])

        let content = ContentState(station: station, trains: trains, now: now)

        #expect(content.trains == .directions(line: TransitLine(mode: .metro, name: "2"), [
            LineDirection(label: "Porte Dauphine", times: []),
            LineDirection(label: "Nation", times: [time(inMinutes: 2)])
        ]))
    }

    @Test func saysNoTrainsInBothDirectionsWhenEveryTrainHasLeft() {
        let trains = board([train(line12, to: "Mairie d'Issy", inMinutes: -0.25, from: southQuay)])

        #expect(ContentState(station: station, trains: trains, now: now).trains == .directions(
            line: TransitLine(mode: .metro, name: "12"),
            [
                LineDirection(label: "Mairie d'Aubervilliers", times: []),
                LineDirection(label: "Mairie d'Issy", times: [])
            ]
        ))
    }

    @Test func dropsTimesMoreThanAnHourAwayAndSaysNoTrainsForADirectionLeftEmpty() {
        let trains = board([
            train(line12, to: "Mairie d'Issy", inMinutes: 154, from: southQuay),
            train(line12, to: "Mairie d'Issy", inMinutes: 8, from: southQuay),
            train(line12, to: "Mairie d'Aubervilliers", inMinutes: 75, from: northQuay)
        ])

        #expect(ContentState(station: station, trains: trains, now: now).trains == .directions(
            line: TransitLine(mode: .metro, name: "12"),
            [
                LineDirection(label: "Mairie d'Aubervilliers", times: []),
                LineDirection(label: "Mairie d'Issy", times: [time(inMinutes: 8)])
            ]
        ))
    }

    @Test func becomesStaleWhenTheFirstShownTrainLeaves() {
        let trains = board([
            train(line12, to: "Mairie d'Issy", inMinutes: 3, from: southQuay),
            train(line12, to: "Mairie d'Aubervilliers", inMinutes: 5, from: northQuay)
        ])

        #expect(ContentState(station: station, trains: trains, now: now).staleDate == time(inMinutes: 3))
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
