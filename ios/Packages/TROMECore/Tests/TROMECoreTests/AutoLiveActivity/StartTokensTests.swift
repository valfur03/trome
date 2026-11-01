import Foundation
import Testing
@testable import TROMECore

/// The start token kept on the phone: a process that iOS wakes at a station may get no token in its seconds, so the
/// ask uses the last one that iOS gave. The Simulator gives no real token: these tests feed the tokens by hand, as the
/// app does with each one that ActivityKit gives, and claim nothing about a real push.
/// A wait that the code never ends fails its test at the time limit, rather than hanging the run.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct StartTokensTests {
    static let old = "aaaa0000aaaa0000aaaa0000aaaa0000"
    static let fresh = "bbbb1111bbbb1111bbbb1111bbbb1111"
    static let launch = Date(timeIntervalSince1970: 1_793_000_000)

    let storage = InMemoryKeyValueStore()
    let wakeLog = WakeLog(storage: InMemoryKeyValueStore())

    func tokens(atLaunch: String? = nil, secondsAfterLaunch: TimeInterval = 0) -> StartTokens {
        let now = Self.launch.addingTimeInterval(secondsAfterLaunch)
        return StartTokens(storage: storage, tokenAtLaunch: atLaunch, wakeLog: wakeLog, launchedAt: Self.launch) { now }
    }

    func keep(_ token: String) {
        StartTokenStore(storage: storage).save(token)
    }

    var kept: String? {
        StartTokenStore(storage: storage).load()
    }

    var lines: [String] {
        wakeLog.entries.reversed().map(\.text)
    }

    /// The silent start of one wake, whose time limit never ends unless `limitEnds`, so that the ask decides.
    func silentStart(_ starter: StubLiveActivityStarter, _ tokens: StartTokens, limitEnds: Bool = false)
        -> SilentStart {
        SilentStart(starter: starter, tokens: tokens, wakeLog: wakeLog) { _ in
            if !limitEnds {
                try await Task.sleep(for: .seconds(3_600))
            }
        }
    }

    // MARK: Criterion 2 and 5: the kept token

    @Test func asksWithTheKeptTokenWhenIOSGaveThisProcessNone() async {
        keep(Self.old)
        let starter = StubLiveActivityStarter(answer: .started)

        let started = await silentStart(starter, tokens()).start(at: AutoTestPlaces.stationA)

        #expect(started)
        #expect(starter.asks == [.init(stationId: "a", startToken: Self.old)])
        #expect(lines.contains("Asks with the kept start token"))
    }

    @Test func aFreshTokenReplacesTheKeptOne() async {
        keep(Self.old)
        let tokens = tokens(secondsAfterLaunch: 2.4)

        tokens.receive(Self.fresh)

        #expect(await tokens.startToken() == StartToken(value: Self.fresh, isKept: false))
        #expect(kept == Self.fresh)
        #expect(lines.last == "iOS gave a start token, 2.4 s after launch (new)")
    }

    @Test func theTokenThatIOSHeldAtLaunchIsUsedAndKept() async {
        let tokens = tokens(atLaunch: Self.fresh)

        #expect(await tokens.startToken() == StartToken(value: Self.fresh, isKept: false))
        #expect(kept == Self.fresh)
        #expect(lines == ["Start token at launch: yes; kept: none"])
    }

    @Test func saysWhenIOSGivesTheTokenThatIsAlreadyKept() {
        keep(Self.old)

        tokens(secondsAfterLaunch: 0.3).receive(Self.old)

        #expect(lines == [
            "Start token at launch: none; kept: yes",
            "iOS gave a start token, 0.3 s after launch (the kept one)"
        ])
    }

    @Test func aTokenThatComesDuringTheWaitIsUsed() async {
        let tokens = tokens()
        let wait = Task { await tokens.startToken() }

        tokens.receive(Self.fresh)

        #expect(await wait.value == StartToken(value: Self.fresh, isKept: false))
    }

    // MARK: Criterion 3: no kept token and none in the 10 seconds

    @Test func noKeptTokenAndNoneFromIOSGivesNoAskThenTheLateTokenIsKeptForTheNextWake() async {
        let starter = StubLiveActivityStarter(answer: .started)
        let firstProcess = tokens()

        let started = await silentStart(starter, firstProcess, limitEnds: true).start(at: AutoTestPlaces.stationA)
        firstProcess.receive(Self.fresh)

        #expect(!started)
        #expect(starter.asks.isEmpty)
        #expect(lines.contains("No start token from iOS within 10 s"))
        #expect(await tokens().startToken() == StartToken(value: Self.fresh, isKept: true))
    }

    // MARK: Criterion 2 and 5: a token refused as invalid

    @Test(arguments: ["BadDeviceToken", "Unregistered"])
    func aTokenRefusedAsInvalidIsForgotten(reason: String) async {
        keep(Self.old)
        let starter = StubLiveActivityStarter(answer: .refused(reason: reason))
        let tokens = tokens()

        let started = await silentStart(starter, tokens).start(at: AutoTestPlaces.stationA)

        #expect(!started)
        #expect(kept == nil)
        #expect(lines.contains("Start token refused as invalid: forgotten"))
        let nextWake = Task { await tokens.startToken() }
        tokens.receive(Self.fresh)
        let next = await nextWake.value
        #expect(next == StartToken(value: Self.fresh, isKept: false), "asked again with the refused one")
    }

    /// Only Apple's reasons that name the token forget it: a fault of the network, of the server or of its setup
    /// says nothing of the token, which may start the next station.
    @Test(arguments: [
        LiveActivityStartAnswer.refused(reason: "no-answer"),
        .refused(reason: "server-error"),
        .refused(reason: "DeviceTokenNotForTopic"),
        .refused(reason: "HTTP 401"),
        .notSetUp,
        .noAnswer
    ])
    func anotherRefusalKeepsTheToken(answer: LiveActivityStartAnswer) async {
        keep(Self.old)
        let starter = StubLiveActivityStarter(answer: answer)

        _ = await silentStart(starter, tokens()).start(at: AutoTestPlaces.stationA)

        #expect(kept == Self.old)
        #expect(!lines.contains("Start token refused as invalid: forgotten"))
    }

    @Test func aFresherTokenThatCameDuringTheAskIsNotForgotten() {
        keep(Self.old)
        let tokens = tokens()
        tokens.receive(Self.fresh)

        tokens.forget(Self.old)

        #expect(kept == Self.fresh)
    }

    // MARK: Criterion 4: the launch line

    @Test func theLaunchLineSaysWhetherIOSHeldATokenAndWhetherOneIsKept() {
        keep(Self.old)

        _ = tokens()

        #expect(lines == ["Start token at launch: none; kept: yes"])
    }

    // MARK: Criterion 5: an update from build 4

    /// Build 1.0.0 (4) has no recorded phone set yet (`PhoneSetTests` reads those of the builds before it): this phone
    /// holds a value under each key that its code writes, the Wake log of its start token included.
    @Test func aPhoneOfBuildFourOpensWithNoKeptToken() async {
        let build4Keys = [
            "autoLiveActivity.state", "autoLiveActivity.mode", "testingTools.wakeLog", "liveActivity.linesPageChoice",
            "stationLiveActivity.inputs", "testingTools.locationSource", "currentStation.id", "testingTools.fakeTrains",
            "liveActivityMaximumDuration", "exampleDuration"
        ]
        for key in build4Keys {
            storage.set(Data("{}".utf8), forKey: key)
        }
        let build4Log = WakeLog(storage: storage)
        build4Log.record(.silentStart, "iOS gave a start token")
        var state = AutoLiveActivityState(arrivalStationId: "a")
        state.pushedStart = PushedStart(stationId: "a", answeredAt: Self.launch)
        AutoLiveActivityStore(storage: storage).save(state)

        #expect(!build4Keys.contains(StartTokenStore.key))
        #expect(kept == nil)
        let starter = StubLiveActivityStarter(answer: .started)
        _ = await silentStart(starter, tokens(), limitEnds: true).start(at: AutoTestPlaces.stationA)
        #expect(starter.asks.isEmpty)
    }
}
