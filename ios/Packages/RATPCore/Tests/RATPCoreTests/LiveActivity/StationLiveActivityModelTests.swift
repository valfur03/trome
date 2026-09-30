import Foundation
import Testing
@testable import RATPCore

@MainActor
final class StubStationLiveActivityClient: StationLiveActivityClient {
    var isShowing = false
    var shownContent: StationActivityAttributes.ContentState?
    var startError: (any Error)?
    var holdsNextUpdate = false
    private var heldUpdate: CheckedContinuation<Void, Never>?
    private(set) var started: [StationActivityAttributes.ContentState] = []
    private(set) var updates: [StationActivityAttributes.ContentState] = []
    private(set) var endCount = 0

    func start(_ content: StationActivityAttributes.ContentState) throws {
        if let startError {
            throw startError
        }
        started.append(content)
        shownContent = content
        isShowing = true
    }

    var isHoldingAnUpdate: Bool {
        heldUpdate != nil
    }

    func update(_ content: StationActivityAttributes.ContentState) async {
        if holdsNextUpdate {
            holdsNextUpdate = false
            await withCheckedContinuation { heldUpdate = $0 }
        }
        updates.append(content)
        shownContent = content
    }

    func end() async {
        endCount += 1
        isShowing = false
    }

    func releaseHeldUpdate() {
        heldUpdate?.resume()
        heldUpdate = nil
    }
}

@MainActor
struct StationLiveActivityModelTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let client = StubStationLiveActivityClient()
    private let abbesses = Station(id: "abbesses", name: "Abbesses", coordinate: Coordinate(48.8844, 2.3384), lines: [])
    private let pigalle = Station(id: "pigalle", name: "Pigalle", coordinate: Coordinate(48.8822, 2.3377), lines: [])

    private var chatelet: Station {
        Station(
            id: "chatelet",
            name: "Châtelet",
            coordinate: Coordinate(48.8586, 2.3474),
            lines: ["1", "4", "7"].enumerated().map { index, name in
                TransitLine(mode: .metro, name: name, stopIds: ["IDFM:\(index * 2)", "IDFM:\(index * 2 + 1)"])
            }
        )
    }

    private var gareDeLEst: Station {
        Station(
            id: "gare-de-l-est",
            name: "Gare de l'Est",
            coordinate: Coordinate(48.8762, 2.3580),
            lines: ["4", "5", "7"].map { TransitLine(mode: .metro, name: $0) }
        )
    }

    private var chateletTrains: NextTrainsState {
        .departures(DepartureBoard(departures: [], stations: [chatelet], now: now), updatedAt: now)
    }

    private func makeModel() -> StationLiveActivityModel {
        StationLiveActivityModel(client: client, now: { [now] in now })
    }

    private func makeModel(savingIn storage: InMemoryKeyValueStore) -> StationLiveActivityModel {
        StationLiveActivityModel(
            client: client,
            store: StationLiveActivityInputsStore(storage: storage),
            now: { [now] in now }
        )
    }

    private func content(_ station: Station, _ trains: NextTrainsState) -> StationActivityAttributes.ContentState {
        StationActivityAttributes.ContentState(station: station, trains: trains, now: now)
    }

    @Test func isHiddenUntilStarted() {
        #expect(makeModel().isShowing == false)
    }

    @Test func knowsALiveActivityThatAlreadyShows() {
        client.isShowing = true

        #expect(makeModel().isShowing)
    }

    @Test func startsTheLiveActivityForTheStation() async {
        let model = makeModel()

        await model.start(station: abbesses, trains: .noLiveData)

        #expect(client.started == [content(abbesses, .noLiveData)])
        #expect(model.isShowing)
        #expect(model.startError == nil)
    }

    @Test func updatesTheLiveActivityThatAlreadyShowsInsteadOfStartingASecondOne() async {
        client.isShowing = true
        let model = makeModel()

        await model.start(station: abbesses, trains: .loading)

        #expect(client.started.isEmpty)
        #expect(client.updates == [content(abbesses, .loading)])
        #expect(model.isShowing)
    }

    @Test(arguments: [StationLiveActivityError.turnedOff, .failed])
    func reportsWhyTheLiveActivityCannotStart(error: StationLiveActivityError) async {
        client.startError = error
        let model = makeModel()

        await model.start(station: abbesses, trains: .loading)

        #expect(model.startError == error)
        #expect(model.isShowing == false)
    }

    @Test func reportsAnUnknownStartProblemAsAFailure() async {
        client.startError = CancellationError()
        let model = makeModel()

        await model.start(station: abbesses, trains: .loading)

        #expect(model.startError == .failed)
    }

    @Test func forgetsTheStartProblemAfterASuccessfulStart() async {
        client.startError = StationLiveActivityError.turnedOff
        let model = makeModel()
        await model.start(station: abbesses, trains: .loading)
        client.startError = nil

        await model.start(station: abbesses, trains: .loading)

        #expect(model.startError == nil)
    }

    @Test func updatesTheShownLiveActivityWithNewTrainsAndStation() async {
        let model = makeModel()
        await model.start(station: abbesses, trains: .loading)

        await model.update(station: pigalle, trains: .noLiveData)

        #expect(client.updates == [content(pigalle, .noLiveData)])
    }

    @Test func appliesTheUpdatesInTheOrderTheAppSendsThem() async {
        let model = makeModel()
        await model.start(station: abbesses, trains: .loading)
        client.holdsNextUpdate = true

        let first = Task { await model.update(station: abbesses, trains: .noLiveData) }
        for _ in 0..<1_000 where !client.isHoldingAnUpdate {
            await Task.yield()
        }
        let second = Task { await model.update(station: pigalle, trains: .noLiveData) }
        for _ in 0..<100 {
            await Task.yield()
        }
        client.releaseHeldUpdate()
        await first.value
        await second.value

        #expect(client.updates == [content(abbesses, .noLiveData), content(pigalle, .noLiveData)])
    }

    @Test func doesNotUpdateALiveActivityThatDoesNotShow() async {
        let model = makeModel()

        await model.update(station: abbesses, trains: .noLiveData)

        #expect(client.updates.isEmpty)
    }

    @Test func stopsTheLiveActivity() async {
        let model = makeModel()
        await model.start(station: abbesses, trains: .loading)

        await model.stop()

        #expect(client.endCount == 1)
        #expect(model.isShowing == false)
    }

    @Test func notesALiveActivityDismissedFromTheLockScreen() async {
        let model = makeModel()
        await model.start(station: abbesses, trains: .loading)
        client.isShowing = false

        model.syncWithSystem()

        #expect(model.isShowing == false)
    }

    @Test func showsTheNextLinesWhenTheRiderAsksForThem() async {
        let model = makeModel()
        await model.start(station: chatelet, trains: chateletTrains)

        await model.showNextLines()

        #expect(client.updates.last?.trains.linesPage?.firstIndex == 2)
        #expect(client.updates.last?.trains.linesPage?.lines.map(\.line.name) == ["7"])
        #expect(model.content == client.updates.last)
    }

    @Test func keepsShowingTheAskedLinesWhenNewTrainsCome() async {
        let model = makeModel()
        await model.start(station: chatelet, trains: chateletTrains)
        await model.showNextLines()

        await model.update(station: chatelet, trains: chateletTrains)

        #expect(client.updates.last?.trains.linesPage?.firstIndex == 2)
    }

    @Test func goesBackToTheFirstLinesAfterTheLastOnes() async {
        let model = makeModel()
        await model.start(station: chatelet, trains: chateletTrains)
        await model.showNextLines()

        await model.showNextLines()

        #expect(client.updates.last?.trains.linesPage?.firstIndex == 0)
    }

    @Test func showsTheFirstLinesOfANewStation() async {
        let model = makeModel()
        await model.start(station: chatelet, trains: chateletTrains)
        await model.showNextLines()

        await model.update(station: pigalle, trains: .noLiveData)
        await model.update(station: chatelet, trains: chateletTrains)

        #expect(client.updates.last?.trains.linesPage?.firstIndex == 0)
    }

    @Test func showsTheFirstLinesOfANewLiveActivity() async {
        let model = makeModel()
        await model.start(station: chatelet, trains: chateletTrains)
        await model.showNextLines()
        await model.stop()

        await model.start(station: chatelet, trains: chateletTrains)

        #expect(client.started.last?.trains.linesPage?.firstIndex == 0)
    }

    @Test func keepsTheLinesThatTheLiveActivityShowedBeforeTheAppStarted() async {
        client.isShowing = true
        client.shownContent = StationActivityAttributes.ContentState(
            station: chatelet,
            trains: chateletTrains,
            now: now,
            firstLineIndex: 2
        )
        let model = makeModel()

        await model.update(station: chatelet, trains: chateletTrains)

        #expect(client.updates.last?.trains.linesPage?.firstIndex == 2)
    }

    @Test func showsTheNextLinesOfTheLiveActivityThatShowedBeforeTheAppStarted() async {
        client.isShowing = true
        client.shownContent = StationActivityAttributes.ContentState(
            station: chatelet,
            trains: chateletTrains,
            now: now,
            firstLineIndex: 2
        )
        let shown = client.shownContent
        let model = makeModel()

        await model.showNextLines()
        #expect(client.updates == [shown])
        await model.update(station: chatelet, trains: chateletTrains)

        #expect(client.updates.last?.trains.linesPage?.firstIndex == 0)
    }

    @Test func showsTheNextLinesAtOnceInAnAppThatIOSStartsForTheTap() async {
        let storage = InMemoryKeyValueStore()
        await makeModel(savingIn: storage).start(station: chatelet, trains: chateletTrains)
        let appStartedForTheTap = makeModel(savingIn: storage)

        await appStartedForTheTap.showNextLines()

        #expect(client.updates.last?.trains.linesPage?.firstIndex == 2)
        #expect(client.updates.last?.trains.linesPage?.lines.map(\.line.name) == ["7"])
        #expect(appStartedForTheTap.content == client.updates.last)
    }

    @Test func doesNotShowTheSavedTrainsOnTheLiveActivityOfAnotherStation() async {
        let storage = InMemoryKeyValueStore()
        await makeModel(savingIn: storage).start(station: chatelet, trains: chateletTrains)
        client.shownContent = StationActivityAttributes.ContentState(station: gareDeLEst, trains: .noLiveData, now: now)
        let appStartedForTheTap = makeModel(savingIn: storage)

        let shown = client.shownContent
        await appStartedForTheTap.showNextLines()

        #expect(client.updates == [shown])
    }

    @Test func forgetsTheSavedTrainsWhenTheLiveActivityStops() async {
        let storage = InMemoryKeyValueStore()
        let model = makeModel(savingIn: storage)
        await model.start(station: chatelet, trains: chateletTrains)

        await model.stop()

        #expect(StationLiveActivityInputsStore(storage: storage).load() == nil)
    }

    @Test func savesNoTrainsWhileTheLiveActivityLoads() async {
        let storage = InMemoryKeyValueStore()
        let model = makeModel(savingIn: storage)
        await model.start(station: chatelet, trains: chateletTrains)

        await model.update(station: gareDeLEst, trains: .loading)

        #expect(StationLiveActivityInputsStore(storage: storage).load() == nil)
    }

    @Test func doesNotChangeTheLinesOfALiveActivityThatDoesNotShow() async {
        let model = makeModel()

        await model.showNextLines()

        #expect(client.updates.isEmpty)
    }
}
