import Foundation
import Testing
@testable import TROMECore

/// A rider at a station with several lines taps to the page of their line, and the pushes of the server, which show
/// the first page to every rider of the station, keep them on it while they carry it.
@MainActor
struct StationLiveActivityPageChoiceTests {
    private let clock = TestClock()
    private let client = StubStationLiveActivityClient()
    private let storage = InMemoryKeyValueStore()
    private let lines = ["4", "5", "7"].map { TransitLine(mode: .metro, name: $0) }

    private var gareDeLEst: Station {
        Station(id: "gare-de-l-est", name: "Gare de l'Est", coordinate: Coordinate(48.8762, 2.3580), lines: lines)
    }

    private var choices: LinesPageChoiceStore {
        LinesPageChoiceStore(storage: storage)
    }

    /// The content of a push: the first page shown, and the first `carried` pages, with trains in `minutes`.
    private func push(inMinutes minutes: Double, carried: Int = 3) -> StationActivityAttributes.ContentState {
        let departures = lines.map {
            Departure(line: $0, destination: "Terminus \($0.name)", time: clock.now.addingTimeInterval(minutes * 60))
        }
        let board = DepartureBoard(departures: departures, stations: [gareDeLEst], now: clock.now)
        var content = StationActivityAttributes.ContentState(
            station: gareDeLEst,
            trains: .departures(board, updatedAt: clock.now),
            now: clock.now,
            carriesEveryPage: true
        )
        if case .lines(var page) = content.trains {
            page.pages = page.pages.map { Array($0.prefix(carried)) }
            content.trains = .lines(page)
        }
        return content
    }

    /// The Live Activity that a push started: the app runs only for the tap, with no trains of its own.
    private func startedByAPush(_ content: StationActivityAttributes.ContentState) -> StationLiveActivityModel {
        client.isShowing = true
        client.shownActivityID = "activity-1"
        client.shownContent = content
        return StationLiveActivityModel(client: client, pageChoices: choices, now: { [clock] in clock.now })
    }

    private func drawn(_ content: StationActivityAttributes.ContentState?, by activityID: String = "activity-1") -> LinesPage? {
        content?.showingThePage(chosenBy: choices.load(), activityID: activityID).trains.linesPage
    }

    private func shownLine(_ page: LinesPage?) -> String? {
        page?.lines.map(\.line.name).joined()
    }

    private func firstTrain(_ page: LinesPage?) -> Date? {
        page?.lines.first?.directions.first?.trains.first?.time
    }

    @Test func aTapShowsTheNextPageFromThePagesOfThePush() async {
        let model = startedByAPush(push(inMinutes: 4))

        await model.showNextLines()

        #expect(shownLine(client.updates.last?.trains.linesPage) == "5")
        #expect(shownLine(drawn(client.updates.last)) == "5")
    }

    @Test func theNextPushKeepsTheTappedPageWithItsOwnMinutes() async {
        let model = startedByAPush(push(inMinutes: 4))
        await model.showNextLines()

        clock.advance(by: 60)
        let nextPush = push(inMinutes: 2)

        #expect(shownLine(nextPush.trains.linesPage) == "4")
        #expect(shownLine(drawn(nextPush)) == "5")
        #expect(firstTrain(drawn(nextPush)) == clock.now.addingTimeInterval(120))
    }

    @Test func aPushThatNoLongerCarriesTheTappedPageShowsTheFirstPage() async {
        let model = startedByAPush(push(inMinutes: 4))
        await model.showNextLines()
        await model.showNextLines()
        #expect(shownLine(drawn(push(inMinutes: 3))) == "7")

        let page = drawn(push(inMinutes: 3, carried: 2))

        #expect(shownLine(page) == "4")
        #expect(firstTrain(page) != nil)
    }

    @Test func theTapsGoRoundThePagesThatThePushCarries() async {
        let model = startedByAPush(push(inMinutes: 4, carried: 2))

        await model.showNextLines()
        #expect(shownLine(drawn(client.updates.last)) == "5")
        await model.showNextLines()

        #expect(shownLine(drawn(client.updates.last)) == "4")
    }

    @Test func aTapAfterAPushGoesOnFromThePageThatTheRiderSees() async {
        let model = startedByAPush(push(inMinutes: 4))
        await model.showNextLines()
        clock.advance(by: 60)
        client.shownContent = push(inMinutes: 3)

        await model.showNextLines()

        #expect(shownLine(drawn(client.updates.last)) == "7")
        #expect(firstTrain(drawn(client.updates.last)) == clock.now.addingTimeInterval(180))
    }

    @Test func theChoiceHoldsOnlyForItsLiveActivityAndStation() async {
        let model = startedByAPush(push(inMinutes: 4))
        await model.showNextLines()

        #expect(shownLine(drawn(push(inMinutes: 3), by: "activity-2")) == "4")
        var otherStation = push(inMinutes: 3)
        otherStation.stationName = "Château Landon"
        #expect(shownLine(otherStation.showingThePage(chosenBy: choices.load(), activityID: "activity-1")
            .trains.linesPage) == "4")
    }

    @Test func aPushWhosePagesDoNotMatchItsLinesNeverShowsAnotherLine() async {
        let model = startedByAPush(push(inMinutes: 4))
        await model.showNextLines()
        var mixed = push(inMinutes: 3)
        if case .lines(var page) = mixed.trains {
            page.pages?.swapAt(1, 2)
            mixed.trains = .lines(page)
        }

        #expect(shownLine(drawn(mixed)) == "4")
    }

    @Test func theAppOpenedAfterATapGoesOnWithTheTappedPage() async {
        let model = startedByAPush(push(inMinutes: 4))
        await model.showNextLines()
        client.shownContent = push(inMinutes: 3)
        let departures = lines.map {
            Departure(line: $0, destination: "Terminus \($0.name)", time: clock.now.addingTimeInterval(120))
        }
        let trains = NextTrainsState.departures(
            DepartureBoard(departures: departures, stations: [gareDeLEst], now: clock.now),
            updatedAt: clock.now
        )

        let reopened = StationLiveActivityModel(client: client, pageChoices: choices, now: { [clock] in clock.now })
        await reopened.update(station: gareDeLEst, trains: trains)

        #expect(shownLine(client.updates.last?.trains.linesPage) == "5")
        _ = model
    }
}
