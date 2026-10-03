import Foundation
import Testing
@testable import TROMECore

private struct AnsweringProvider: DeparturesProvider {
    let answer: DeparturesAnswer

    func departures(at stations: [Station]) async throws -> [Departure] {
        answer.departures
    }

    func departuresAnswer(at stations: [Station]) async throws -> DeparturesAnswer {
        answer
    }
}

extension NextTrainsModelTests {
    nonisolated private static let primAnsweredAt = Fixture.date("2026-09-26T10:00:00Z")
    nonisolated private static let threeMinutesLater = primAnsweredAt.addingTimeInterval(3 * 60)

    private var abbessesStopArea: Station {
        PRIMDeparturesProviderTests().abbesses
    }

    private func serverModel(now: Date) -> NextTrainsModel {
        let client = ServerStubHTTPClient { _ in try PRIMDeparturesProviderTests.timesReply() }
        return NextTrainsModel(
            provider: PRIMDeparturesProvider(source: .server(.test), httpClient: client),
            now: { now }
        )
    }

    private func shownTimes(of content: StationActivityAttributes.ContentState) -> [Date] {
        (content.trains.linesPage?.lines ?? []).flatMap(\.directions).flatMap(\.trains).map(\.time).sorted()
    }

    @Test func takesTheTimeWhenPRIMGaveTheAnswerAsTheTimeBaseOfTheTrains() async {
        let model = serverModel(now: Self.threeMinutesLater)

        await model.refresh(for: abbessesStopArea)

        guard case .departures(_, let updatedAt) = model.state else {
            Issue.record("No trains in \(model.state)")
            return
        }
        #expect(updatedAt == Self.primAnsweredAt)
    }

    @Test func showsNoTrainThatLeftBetweenTheAnswerOfPRIMAndNow() async {
        let model = serverModel(now: Self.threeMinutesLater)
        await model.refresh(for: abbessesStopArea)

        let content = StationActivityAttributes.ContentState(
            station: abbessesStopArea,
            trains: model.state,
            now: Self.threeMinutesLater
        )

        let firstTrainLeftAt = Fixture.date("2026-09-26T10:02:30Z")
        #expect(!shownTimes(of: content).isEmpty)
        #expect(!shownTimes(of: content).contains(firstTrainLeftAt))
        #expect(shownTimes(of: content).allSatisfy { $0 > Self.threeMinutesLater })
        #expect(content.staleDate == Fixture.date("2026-09-26T10:04:00Z"))
    }

    @Test func letsAnOlderAnswerWhoseNextTrainWasOverAnHourAwayGoStaleAtOnce() async {
        let train = Departure(
            line: abbessesStopArea.lines[0],
            destination: "Mairie d'Issy",
            time: Self.primAnsweredAt.addingTimeInterval(61 * 60)
        )
        let model = NextTrainsModel(
            provider: AnsweringProvider(answer: DeparturesAnswer(departures: [train], answeredAt: Self.primAnsweredAt)),
            now: { Self.threeMinutesLater }
        )
        await model.refresh(for: abbessesStopArea)

        let content = StationActivityAttributes.ContentState(
            station: abbessesStopArea,
            trains: model.state,
            now: Self.threeMinutesLater
        )

        #expect(content.trains.linesPage?.nextTrainIsOverAnHourAway == true)
        #expect(content.staleDate == Self.primAnsweredAt.addingTimeInterval(60))
        #expect(content.staleDate.map { $0 < Self.threeMinutesLater } == true)
    }

    @Test func neverTakesAnAnswerTimeAfterTheClockOfThePhone() async {
        let train = Departure(
            line: abbessesStopArea.lines[0],
            destination: "Mairie d'Issy",
            time: Self.primAnsweredAt.addingTimeInterval(5 * 60)
        )
        let answeredInTheFuture = Self.primAnsweredAt.addingTimeInterval(30)
        let model = NextTrainsModel(
            provider: AnsweringProvider(answer: DeparturesAnswer(departures: [train], answeredAt: answeredInTheFuture)),
            now: { Self.primAnsweredAt }
        )

        await model.refresh(for: abbessesStopArea)

        guard case .departures(_, let updatedAt) = model.state else {
            Issue.record("No trains in \(model.state)")
            return
        }
        #expect(updatedAt == Self.primAnsweredAt)
    }

    @Test func keepsTheTimeOfThePhoneAsTheTimeBaseOfADirectPRIMAnswer() async {
        let client = StubHTTPClient { _ in (try Fixture.data("stop-monitoring-abbesses-stop-area"), 200) }
        let model = NextTrainsModel(
            provider: PRIMDeparturesProvider(apiKey: "test-key", httpClient: client),
            now: { Self.threeMinutesLater }
        )

        await model.refresh(for: abbessesStopArea)

        guard case .departures(_, let updatedAt) = model.state else {
            Issue.record("No trains in \(model.state)")
            return
        }
        #expect(updatedAt == Self.threeMinutesLater)
    }
}
