import Foundation
import Testing
@testable import TROMECore

/// The silent start: iOS wakes the app at a station, and the server starts the Live Activity. When it does not, no
/// notification stands in: the wake log says why, in one line, and the rider who opens the app there gets it.
/// `StubNotificationPermission` is the only path from the core to the notifications of iOS, and it cannot send one.
extension AutoLiveActivityModelTests {
    /// Le Parc de Saint-Maur, and the fix of the two "entered" events that iOS gave at 16:58:46 on the outing of
    /// 2026-10-18: 136 m from the station point, ±13 m, 0 s old.
    static let leParc = Station(
        id: "IDFM:monomodalStopPlace:43234",
        name: "Le Parc de Saint-Maur",
        coordinate: Coordinate(48.80541, 2.486624),
        lines: []
    )
    static let leParcEdge = Coordinate(48.806633, 2.486624)

    func silentStart(
        _ starter: StubLiveActivityStarter,
        tokens: StubStartTokens = StubStartTokens(),
        backgroundTimeRemaining: (@MainActor () -> TimeInterval)? = nil
    ) -> SilentStart {
        let clock = clock
        return SilentStart(
            starter: starter,
            tokens: tokens,
            wakeLog: wakeLog,
            backgroundTimeRemaining: backgroundTimeRemaining,
            now: { clock.now },
            sleep: { try await clock.sleep(for: $0) }
        )
    }

    func sameArrivalLine(at station: Station) -> String {
        ArrivalOutcome.alreadyArrived(station).summary
    }

    var silentStartLines: [String] {
        wakeLog.entries.reversed().filter { $0.kind == .silentStart }.map(\.text)
    }

    func noStartLine(at station: Station = Places.stationA, because cause: String) -> String {
        "No start at \(station.name), no notification: \(cause)"
    }

    @Test(arguments: [LiveActivityStartAnswer.started, .alreadyStarted])
    func startsThroughTheServerWithNoNotificationWhenIOSWakesTheAppAtAStation(answer: LiveActivityStartAnswer) async {
        let starter = StubLiveActivityStarter(answer: answer)
        let model = makeModel(silentStart: silentStart(starter))

        await wake(model, at: Places.fiftyMetersFromA)

        #expect(starter.asks == [.init(stationId: "a", startToken: StubStartTokens.token)])
        #expect(arrivalsWithNoStart.isEmpty)
        #expect(client.started.isEmpty)
        #expect(silentStartLines == [
            "Asks the server to start the Live Activity: Station A",
            "Asks with this launch's start token",
            "Answer: \(answer.summary), after 0 s"
        ])
        #expect(wakeLog.entries.contains { $0.kind == .decision && $0.text == "Arrived in the background: Station A" })
    }

    @Test(arguments: [
        (LiveActivityStartAnswer.refused(reason: "BadDeviceToken"), "refused (BadDeviceToken)"),
        (.refused(reason: "no-answer"), "refused (no-answer)"),
        (.refused(reason: "HTTP 401"), "refused (HTTP 401)"),
        (.notSetUp, "not set up"),
        (.noAnswer, "no answer")
    ])
    func writesWhyAndSendsNoNotificationWhenTheServerDoesNotStartIt(answer: LiveActivityStartAnswer, cause: String)
        async {
        let starter = StubLiveActivityStarter(answer: answer)
        let model = makeModel(silentStart: silentStart(starter))

        await wake(model, at: Places.fiftyMetersFromA)
        await wake(model, at: Places.fiftyMetersFromA)

        #expect(starter.asks.count == 1)
        #expect(client.started.isEmpty)
        #expect(arrivalsWithNoStart == [Places.stationA.name])
        let forgotten = answer.refusesTheStartToken ? ["Start token refused as invalid: forgotten"] : []
        #expect(silentStartLines == [
            "Asks the server to start the Live Activity: Station A",
            "Asks with this launch's start token"
        ] + forgotten + [
            noStartLine(because: "\(cause), after 0 s")
        ])
    }

    /// A held answer that the code never ends fails the test at the time limit, rather than hanging the run.
    @Test(.timeLimit(.minutes(1))) func writesWhyAndSendsNoNotificationWhenTheServerTakesMoreThanTenSeconds() async {
        let starter = StubLiveActivityStarter(answer: nil)
        let model = makeModel(silentStart: silentStart(starter))
        clock.letTimersFire(upTo: 10)

        await wake(model, at: Places.fiftyMetersFromA)

        #expect(starter.asks.count == 1)
        #expect(client.started.isEmpty)
        #expect(arrivalsWithNoStart == [Places.stationA.name])
        #expect(silentStartLines == [
            "Asks the server to start the Live Activity: Station A",
            "Asks with this launch's start token",
            noStartLine(because: "No answer within 10 s")
        ])
    }

    @Test(.timeLimit(.minutes(1))) func takesAnAnswerThatComesWithinTenSeconds() async {
        let starter = StubLiveActivityStarter(answer: nil)
        let model = makeModel(silentStart: silentStart(starter))
        clock.letTimersFire(upTo: 9)

        let wake = Task { await wake(model, at: Places.fiftyMetersFromA) }
        await waitUntil { starter.asks.count == 1 }
        starter.answer(with: .started)
        await wake.value

        #expect(arrivalsWithNoStart.isEmpty)
        #expect(silentStartLines.last == "Answer: started, after 0 s")
    }

    @Test(.timeLimit(.minutes(1))) func writesWhyAndSendsNoNotificationWhenIOSGaveNoStartToken() async {
        let starter = StubLiveActivityStarter(answer: .started)
        let tokens = StubStartTokens()
        tokens.token = nil
        let model = makeModel(silentStart: silentStart(starter, tokens: tokens))
        clock.letTimersFire(upTo: 10)

        await wake(model, at: Places.fiftyMetersFromA)

        #expect(starter.asks.isEmpty)
        #expect(client.started.isEmpty)
        #expect(arrivalsWithNoStart == [Places.stationA.name])
        #expect(silentStartLines == [
            "Asks the server to start the Live Activity: Station A",
            noStartLine(because: "No start token from iOS within 10 s")
        ])
    }

    @Test func writesWhyAndSendsNoNotificationWithNoAskWhenLiveActivitiesAreOffInSettings() async {
        let starter = StubLiveActivityStarter(answer: .started)
        client.areActivitiesEnabled = false
        let model = makeModel(silentStart: silentStart(starter))

        await wake(model, at: Places.fiftyMetersFromA)

        #expect(starter.asks.isEmpty)
        #expect(client.started.isEmpty)
        #expect(silentStartLines == [noStartLine(because: "Live Activities are off in Settings")])
    }

    /// A build with no push code, or with no server: nothing asks, and nothing stands in.
    @Test func writesWhyAndSendsNoNotificationInABuildWithNoSilentStart() async {
        let model = makeModel(silentStart: nil)

        await wake(model, at: Places.fiftyMetersFromA)

        #expect(client.started.isEmpty)
        #expect(silentStartLines == [noStartLine(because: "the silent start is off in this build")])
    }

    /// The other half of a start that does not come: the rider who opens the app at the station gets the Live
    /// Activity at once, as with no silent start.
    @Test func openingTheAppAtTheStationAfterARefusedStartStartsTheLiveActivity() async {
        let starter = StubLiveActivityStarter(answer: .refused(reason: "BadDeviceToken"))
        let model = makeModel(silentStart: silentStart(starter))
        gps.report(Places.fiftyMetersFromA)
        await waitUntil { !arrivalsWithNoStart.isEmpty }
        #expect(client.started.isEmpty)

        await activate(model)

        #expect(client.started.map(\.stationName) == ["Station A"])
        #expect(starter.asks.count == 1)
    }

    /// The outing of 2026-10-18: iOS gave "entered Le Parc" twice in the same second; the second comes here while
    /// the server is still asked.
    @Test(.timeLimit(.minutes(1))) func asksOnceForTheTwoEventsOfOneArrival() async {
        let starter = StubLiveActivityStarter(answer: nil)
        let model = makeModel(catalog: StationCatalog(stations: [Self.leParc]), silentStart: silentStart(starter))
        let entered = RegionEvent.entered(regionId: "arrival:\(Self.leParc.id)")
        let fix = PositionFix(coordinate: Self.leParcEdge, accuracyMeters: 13, timestamp: clock.now)
        let sameArrival = sameArrivalLine(at: Self.leParc)

        let first = Task { await model.handleRegionEvent(entered, lastKnownFix: fix) }
        await waitUntil { starter.asks.count == 1 }
        let second = Task { await model.handleRegionEvent(entered, lastKnownFix: fix) }
        await waitUntil { wakeLog.entries.contains { $0.text == sameArrival } }
        starter.answer(with: .started)
        await first.value
        await second.value

        #expect(starter.asks == [.init(stationId: Self.leParc.id, startToken: StubStartTokens.token)])
        #expect(arrivalsWithNoStart.isEmpty)
        #expect(client.started.isEmpty)
        #expect(silentStartLines.last == "Answer: started, after 0 s")
    }

    @Test func neverAsksWhenTheRiderStartedTheLiveActivityByHand() async {
        let starter = StubLiveActivityStarter(answer: .started)
        let model = makeModel(silentStart: silentStart(starter))
        await activate(model)
        await model.startByHand(Places.stationA)
        model.setAppPhase(.background)

        await wake(model, at: Places.fiftyMetersFromA)

        #expect(starter.asks.isEmpty)
        #expect(arrivalsWithNoStart.isEmpty)
        #expect(client.started.count == 1)
    }

    @Test(.timeLimit(.minutes(1))) func theAppOpenedDuringTheAskStartsNoLiveActivityOfItsOwn() async {
        let starter = StubLiveActivityStarter(answer: nil)
        let model = makeModel(silentStart: silentStart(starter))
        let sameArrival = sameArrivalLine(at: Places.stationA)

        let wake = Task { await wake(model, at: Places.fiftyMetersFromA) }
        await waitUntil { starter.asks.count == 1 }
        await activate(model)
        gps.report(Places.fiftyMetersFromA)
        await waitUntil { wakeLog.entries.contains { $0.text == sameArrival } }
        #expect(client.started.isEmpty)
        starter.answer(with: .started)
        await wake.value

        #expect(arrivalsWithNoStart.isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func stillWritesWhyOnceTheRiderLeftDuringTheAsk() async {
        let starter = StubLiveActivityStarter(answer: nil)
        let model = makeModel(silentStart: silentStart(starter))

        let arrival = Task { await wake(model, at: Places.fiftyMetersFromA) }
        await waitUntil { starter.asks.count == 1 }
        await wake(model, at: Places.fourHundredMetersFromA)
        starter.answer(with: .notSetUp)
        await arrival.value

        #expect(client.started.isEmpty)
        #expect(silentStartLines.last == noStartLine(because: "not set up, after 0 s"))
    }

    /// What a walk must read to tell a suspension from a rule: the background time that iOS still gives at the ask,
    /// and an ask that lasts past its limit, as only a suspended app lets it.
    @Test func tellsTheBackgroundTimeThatIOSStillGivesAtTheAsk() async {
        let starter = StubLiveActivityStarter(answer: .started)
        let model = makeModel(silentStart: silentStart(starter, backgroundTimeRemaining: { 24.6 }))

        await wake(model, at: Places.fiftyMetersFromA)

        #expect(silentStartLines.first == """
            Asks the server to start the Live Activity: Station A (24 s of background time left)
            """)
    }

    @Test(.timeLimit(.minutes(1))) func tellsThatIOSSuspendedTheAppWhenTheAskLastsPastItsLimit() async {
        let starter = StubLiveActivityStarter(answer: nil)
        let model = makeModel(silentStart: silentStart(starter))

        let wake = Task { await wake(model, at: Places.fiftyMetersFromA) }
        await waitUntil { starter.asks.count == 1 }
        clock.advance(by: 40)
        starter.answer(with: .started)
        await wake.value

        #expect(silentStartLines.last == """
            Answer: started, after 40 s; the ask lasted 40 s for a limit of 10 s: iOS suspended the app
            """)
    }

    @Test(.timeLimit(.minutes(1))) func tellsNoSuspensionForAnAskThatEndsWithinItsLimit() async {
        let starter = StubLiveActivityStarter(answer: nil)
        let model = makeModel(silentStart: silentStart(starter))

        let wake = Task { await wake(model, at: Places.fiftyMetersFromA) }
        await waitUntil { starter.asks.count == 1 }
        clock.advance(by: 11)
        starter.answer(with: .noAnswer)
        await wake.value

        let cause = "\(LiveActivityStartAnswer.noAnswer.summary), after 11 s"
        #expect(silentStartLines.contains(noStartLine(because: cause)))
    }
}
