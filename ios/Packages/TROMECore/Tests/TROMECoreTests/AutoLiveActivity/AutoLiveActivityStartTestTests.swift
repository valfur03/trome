import Foundation
import Testing
@testable import TROMECore

/// The test of the start, from the record of a build for a walk: at a desk, the rider asks the server, as a wake at a
/// station does, to start the Live Activity of the nearest station, so that the push links are seen before a walk.
extension AutoLiveActivityModelTests {
    func phone(at position: Coordinate) async {
        gps.report(position)
        await waitUntil { locationService.position == position }
    }

    func testTheStart(_ model: AutoLiveActivityModel) async -> Bool {
        let asked = model.testTheStart()
        await model.startTestTask?.value
        return asked
    }

    /// AC 1: the nearest station of the list, whatever its distance, through the lines of a wake.
    @Test func asksForTheNearestStationWithTheLinesOfAWake() async {
        let starter = StubLiveActivityStarter(answer: .started)
        let model = makeModel(silentStart: silentStart(starter))
        await phone(at: Places.fourHundredMetersFromA)

        #expect(await testTheStart(model))

        #expect(starter.asks == [.init(stationId: "a", startToken: StubStartTokens.token)])
        #expect(wakeLog.entries.contains {
            $0.kind == .decision && $0.text == "Test of the start by the rider: Station A, 400 m away"
        })
        #expect(silentStartLines == [
            "Asks the server to start the Live Activity: Station A",
            "Asks with this launch's start token",
            "Answer: started, after 0 s"
        ])
        #expect(client.started.isEmpty)
    }

    /// AC 1: a start that does not come writes the line of a wake, with its cause.
    @Test(arguments: [
        (LiveActivityStartAnswer.refused(reason: "BadDeviceToken"), "refused (BadDeviceToken), after 0 s"),
        (.notSetUp, "not set up, after 0 s")
    ])
    func writesWhyTheStartDidNotComeAsAWakeDoes(answer: LiveActivityStartAnswer, cause: String) async {
        let model = makeModel(silentStart: silentStart(StubLiveActivityStarter(answer: answer)))
        await phone(at: Places.fourHundredMetersFromA)

        #expect(await testTheStart(model))

        #expect(silentStartLines.last == noStartLine(because: cause))
        #expect(!keeper.isKeeping)
    }

    @Test(.timeLimit(.minutes(1))) func writesNoStartTokenAsAWakeDoes() async {
        let tokens = StubStartTokens()
        tokens.token = nil
        let model = makeModel(silentStart: silentStart(StubLiveActivityStarter(answer: .started), tokens: tokens))
        await phone(at: Places.fourHundredMetersFromA)
        clock.letTimersFire(upTo: 10)

        #expect(await testTheStart(model))

        #expect(silentStartLines.last == noStartLine(because: "No start token from iOS within 10 s"))
    }

    /// AC 2: the rider locks the phone right after the tap: the location keeps the app running during the ask.
    @Test(.timeLimit(.minutes(1))) func keepsTheAppRunningDuringTheAsk() async {
        let starter = StubLiveActivityStarter(answer: nil)
        let model = makeModel(silentStart: silentStart(starter))
        await phone(at: Places.fourHundredMetersFromA)

        #expect(model.testTheStart())
        model.setAppPhase(.background)
        await waitUntil { starter.asks.count == 1 }

        #expect(keeper.isKeeping)
        starter.answer(with: .refused(reason: "BadDeviceToken"))
        await model.startTestTask?.value
        #expect(!keeper.isKeeping)
    }

    @Test func asksNothingWithNoPosition() async {
        let starter = StubLiveActivityStarter(answer: .started)
        let model = makeModel(silentStart: silentStart(starter))

        #expect(!(await testTheStart(model)))

        #expect(starter.asks.isEmpty)
        #expect(wakeLog.entries.first?.text == "Test of the start: no position, nothing asked")
    }

    /// A wake does not ask while a Live Activity shows: the server would bring a second one.
    @Test func asksNothingWhileALiveActivityShows() async {
        let starter = StubLiveActivityStarter(answer: .started)
        let model = makeModel(silentStart: silentStart(starter))
        await phone(at: Places.fourHundredMetersFromA)
        await model.startByHand(Places.stationA)

        #expect(!(await testTheStart(model)))

        #expect(starter.asks.isEmpty)
        #expect(wakeLog.entries.first?.text == "Test of the start: a Live Activity shows, nothing asked")
    }

    /// A build with no silent start (the Simulator) says it, as a wake does, and the row does not say that it left.
    @Test func saysThatABuildWithNoSilentStartAsksNothing() async {
        let model = makeModel()
        await phone(at: Places.fourHundredMetersFromA)

        #expect(!(await testTheStart(model)))

        #expect(silentStartLines == [noStartLine(because: "the silent start is off in this build")])
    }

    /// AC 2: at a desk far from the station, the Live Activity that the push brings stays: the position of the desk
    /// does not end it, and the 45 minutes do, at the latest when the app next runs.
    @Test func theLiveActivityOfATestAtADeskStaysUntilThe45Minutes() async {
        let model = makeModel(silentStart: silentStart(StubLiveActivityStarter(answer: .started)))
        await phone(at: Places.fourHundredMetersFromA)
        #expect(await testTheStart(model))

        pushLands(at: Places.stationA)
        await activate(model)
        await model.evaluate(position: Places.fourHundredMetersFromA)

        #expect(model.shownStation == Places.stationA)
        #expect(client.endCount == 0)

        clock.advance(by: AutoLiveActivityRules.defaultMaximumDuration)
        await model.evaluate(position: nil)

        #expect(client.endCount == 1)
        #expect(wakeLog.entries.contains { $0.text == "Live Activity ended: 45 min after it started" })
    }

    /// A test within 250 meters of the station ends by distance, as an arrival does.
    @Test func theLiveActivityOfATestNearTheStationEndsWhenThePhoneLeaves() async {
        let model = makeModel(silentStart: silentStart(StubLiveActivityStarter(answer: .started)))
        await phone(at: Places.twoHundredMetersFromA)
        #expect(await testTheStart(model))
        pushLands(at: Places.stationA)
        #expect(model.shownStation == Places.stationA)

        await activate(model)
        gps.report(Places.fourHundredMetersFromA)
        await waitUntil { client.endCount == 1 }

        #expect(model.shownStation == nil)
    }

    /// AC 3: the ask of a test sends the request of a wake: the station in the path and the start token in the body,
    /// and nothing of the position.
    @Test func sendsTheStationAndTheStartTokenAndNoPosition() async throws {
        let http = ServerStubHTTPClient { _ in .init(body: Data(#"{"result":"started"}"#.utf8), status: 200, headers: [:]) }
        let starter = ServerLiveActivityStarter(server: .test, httpClient: http)
        let clock = clock
        let model = makeModel(silentStart: SilentStart(
            starter: starter, tokens: StubStartTokens(), wakeLog: wakeLog, now: { clock.now }
        ))
        await phone(at: Places.fourHundredMetersFromA)

        #expect(await testTheStart(model))

        let sent = try #require(http.requests.first)
        let ofAWake = starter.request(stationId: Places.stationA.id, startToken: StubStartTokens.token)
        #expect(http.requests.count == 1)
        #expect(sent.url == ofAWake.url)
        #expect(sent.allHTTPHeaderFields == ofAWake.allHTTPHeaderFields)
        let body = try JSONSerialization.jsonObject(with: try #require(sent.httpBody)) as? [String: String]
        #expect(body == ["startToken": StubStartTokens.token])
        let whole = "\(sent.url?.absoluteString ?? "") \(sent.allHTTPHeaderFields ?? [:]) \(String(decoding: sent.httpBody ?? Data(), as: UTF8.self))"
        #expect(!whole.contains("48.85"))
        #expect(!whole.contains("2.35"))
    }

    /// The state that an earlier build kept, with a start that the server took at an arrival, reads as near.
    @Test func aPushedStartKeptByAnEarlierBuildWasNear() throws {
        let kept = Data(#"{"stationId":"a","answeredAt":0}"#.utf8)

        let pushed = try JSONDecoder().decode(PushedStart.self, from: kept)

        #expect(pushed.hasBeenNear)
    }
}
