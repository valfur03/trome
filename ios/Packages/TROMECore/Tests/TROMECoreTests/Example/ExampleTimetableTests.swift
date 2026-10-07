import Foundation
import Testing
@testable import TROMECore

struct ExampleTimetableTests {
    // The phone locked within 10 s of the tap, then iOS suspends the app about 9 s later.
    private static let lastUpdateBeforeTheSuspension: TimeInterval = 19

    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let catalog: StationCatalog
    private let hub: [Station]
    private let chatelet: Station

    init() throws {
        catalog = try StationCatalog.bundled()
        chatelet = try #require(catalog.station(withId: ExampleTimetable.stationId))
        hub = catalog.hubStations(of: chatelet)
    }

    private func content(
        after seconds: TimeInterval,
        firstLineIndex: Int = 0
    ) -> StationActivityAttributes.ContentState {
        let now = start.addingTimeInterval(seconds)
        let trains = ExampleTimetable(start: start).trains(at: hub, now: now)
        return StationActivityAttributes.ContentState(
            station: chatelet,
            trains: trains,
            now: now,
            firstLineIndex: firstLineIndex
        )
    }

    private func pages(after seconds: TimeInterval) throws -> [LinesPage] {
        var pages = [try #require(content(after: seconds).trains.linesPage)]
        while let last = pages.last, last.nextFirstIndex != 0, pages.count < 10 {
            pages.append(try #require(content(after: seconds, firstLineIndex: last.nextFirstIndex).trains.linesPage))
        }
        return pages
    }

    @Test func theExampleIsChateletWithItsMetroAndRERLinesOnSeveralPages() throws {
        let page = try #require(content(after: 0).trains.linesPage)

        #expect(chatelet.name == "Châtelet")
        #expect(Set(page.allLines.map(\.name)) == ["1", "4", "7", "11", "14", "A", "B", "D"])
        #expect(Set(page.allLines.map(\.mode)) == [.metro, .rer])
        #expect(page.hasOtherLines)
        #expect(try pages(after: 0).count > 1)
    }

    @Test(arguments: Array(stride(from: 0.0, through: 600, by: 15)))
    func everyDirectionOfEveryLineHasTrainsThatHaveNotLeft(after seconds: TimeInterval) throws {
        let now = start.addingTimeInterval(seconds)
        let lines = try pages(after: seconds).flatMap(\.lines)

        #expect(lines.count == 8)
        for line in lines {
            let endsAtChatelet = line.line.name == "11"
            #expect(line.directions.count == (endsAtChatelet ? 1 : 2), "\(line.line.name)")
            for direction in line.directions {
                #expect(!direction.trains.isEmpty, "\(line.line.name) \(direction.label)")
                #expect(direction.trains.allSatisfy { $0.time > now }, "\(line.line.name) \(direction.label)")
            }
        }
    }

    @Test(arguments: Array(stride(from: 0.0, through: 300, by: 10)))
    func noTrainOfTheHubLeavesInTheFirstFiveMinutes(after seconds: TimeInterval) throws {
        let staleDate = try #require(content(after: seconds).staleDate)

        #expect(staleDate > start.addingTimeInterval(5 * 60))
    }

    @Test(arguments: [
        (minute: 1, laDefense: [5, 8], vincennes: [7, 10]),
        (minute: 3, laDefense: [3, 6], vincennes: [5, 8]),
        (minute: 5, laDefense: [1, 4], vincennes: [3, 6])
    ])
    func theLockScreenCountsDownWhileTheAppIsSuspended(
        minute: Int,
        laDefense: [Int],
        vincennes: [Int]
    ) throws {
        let lastUpdate = content(after: Self.lastUpdateBeforeTheSuspension)
        let now = start.addingTimeInterval(TimeInterval(minute * 60))
        let page = try #require(lastUpdate.trains.linesPage)
        let line = try #require(page.lines.first)
        let shown = Dictionary(uniqueKeysWithValues: line.directions.map { direction in
            (direction.label, direction.trains.map { $0.countdownMinutes(at: now) })
        })

        #expect(line.line.name == "1")
        #expect(try #require(lastUpdate.staleDate) > now)
        #expect(line.directions.allSatisfy { $0.trains.allSatisfy { $0.time > now } })
        #expect(shown == ["La Défense": laDefense, "Château de Vincennes": vincennes])
    }

    @Test func theTimesCountDownAndRenew() {
        let timetable = ExampleTimetable(start: start)
        let first = timetable.departures(at: hub, now: start)
        let later = timetable.departures(at: hub, now: start.addingTimeInterval(600))

        #expect(Set(first.map(\.time)) != Set(later.map(\.time)))
        #expect(later.allSatisfy { $0.time > start.addingTimeInterval(600) })
        #expect(later.count == first.count)
    }
}
