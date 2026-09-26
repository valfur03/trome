import Foundation
import Testing
@testable import RATPCore

struct StationActivityContentTests {
    private typealias ContentState = StationActivityAttributes.ContentState

    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let line12 = TransitLine(mode: .metro, name: "12", stopIds: ["IDFM:1"])
    private let rerA = TransitLine(mode: .rer, name: "A", stopIds: ["IDFM:monomodalStopPlace:2"])
    private var station: Station {
        Station(id: "abbesses", name: "Abbesses", coordinate: Coordinate(48.8844, 2.3384), lines: [line12, rerA])
    }

    private func time(inMinutes minutes: Double) -> Date {
        now.addingTimeInterval(minutes * 60)
    }

    private func board(_ groups: [DepartureGroup]) -> NextTrainsState {
        .departures(DepartureBoard(groups: groups), updatedAt: now)
    }

    @Test func showsTheStationName() {
        let content = ContentState(station: station, trains: .loading, now: now)

        #expect(content.stationName == "Abbesses")
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

    @Test func showsOneLineInOneDirectionWithoutItsStopIds() {
        let trains = board([
            DepartureGroup(line: line12, destination: "Mairie d'Issy", times: [time(inMinutes: 3), time(inMinutes: 9)]),
            DepartureGroup(line: line12, destination: "Mairie d'Aubervilliers", times: [time(inMinutes: 1)]),
            DepartureGroup(line: rerA, destination: "Marne-la-Vallée", times: [time(inMinutes: 2)])
        ])

        let content = ContentState(station: station, trains: trains, now: now)

        let row = StationActivityAttributes.DepartureRow(
            line: TransitLine(mode: .metro, name: "12"),
            destination: "Mairie d'Issy",
            times: [time(inMinutes: 3), time(inMinutes: 9)]
        )
        #expect(content.trains == .departures([row]))
    }

    @Test func skipsADirectionWhoseTrainsHaveAllLeft() {
        let trains = board([
            DepartureGroup(line: line12, destination: "Mairie d'Issy", times: [time(inMinutes: -2)]),
            DepartureGroup(
                line: line12,
                destination: "Mairie d'Aubervilliers",
                times: [time(inMinutes: -5), time(inMinutes: 4)]
            )
        ])

        let content = ContentState(station: station, trains: trains, now: now)

        let row = StationActivityAttributes.DepartureRow(
            line: TransitLine(mode: .metro, name: "12"),
            destination: "Mairie d'Aubervilliers",
            times: [time(inMinutes: 4)]
        )
        #expect(content.trains == .departures([row]))
    }

    @Test func saysThereIsNoDataWhenEveryTrainHasLeft() {
        let trains = board([DepartureGroup(line: line12, destination: "Mairie d'Issy", times: [time(inMinutes: -2)])])

        #expect(ContentState(station: station, trains: trains, now: now).trains == .noData)
    }

    @Test func skipsATrainThatHasJustLeft() {
        let trains = board([
            DepartureGroup(
                line: line12,
                destination: "Mairie d'Issy",
                times: [time(inMinutes: -0.25), time(inMinutes: 4)]
            )
        ])

        let content = ContentState(station: station, trains: trains, now: now)

        let row = StationActivityAttributes.DepartureRow(
            line: TransitLine(mode: .metro, name: "12"),
            destination: "Mairie d'Issy",
            times: [time(inMinutes: 4)]
        )
        #expect(content.trains == .departures([row]))
    }

    @Test func becomesStaleWhenTheShownTrainLeaves() {
        let trains = board([
            DepartureGroup(line: line12, destination: "Mairie d'Issy", times: [time(inMinutes: 3), time(inMinutes: 9)])
        ])

        #expect(ContentState(station: station, trains: trains, now: now).staleDate == time(inMinutes: 3))
    }

    @Test func becomesStaleWhenTheTrainsTakeTooLongToLoad() {
        let content = ContentState(station: station, trains: .loading, now: now)

        #expect(content.staleDate == now.addingTimeInterval(ContentState.loadingTimeout))
    }

    @Test func neverBecomesStaleWithoutTrainTimes() {
        #expect(ContentState(station: station, trains: .noLiveData, now: now).staleDate == nil)
    }
}
