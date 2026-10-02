import Foundation
import Testing
@testable import RATPCore

struct BranchEndRowTests {
    private static let ends = ["Saint-Denis - Université", "Asnières - Gennevilliers - Les Courtilles"]
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func train(inMinutes minutes: Double, to end: Int) -> LineDirection.Train {
        LineDirection.Train(time: now.addingTimeInterval(minutes * 60), destination: Self.ends[end])
    }

    private func north(
        _ rows: [[LineDirection.Train]],
        overAnHour: [Bool] = [false, false],
        directionOverAnHour: Bool = false
    ) -> LineDirection {
        let endTrains = zip(Self.ends, zip(rows, overAnHour)).map { end, row in
            BranchEndTrains(end: end, trains: row.0, nextTrainIsOverAnHourAway: row.1)
        }
        return LineDirection(
            label: Self.ends.joined(separator: " / "),
            trains: Array(rows.flatMap { $0 }.sorted { $0.time < $1.time }.prefix(2)),
            nextTrainIsOverAnHourAway: directionOverAnHour,
            branchEnds: Self.ends,
            trainsOfEachEnd: endTrains
        )
    }

    @Test func showsTheTrainsOfAnEndWithOneOrTwoTrains() {
        let direction = north([
            [train(inMinutes: 3, to: 0), train(inMinutes: 9, to: 0)],
            [train(inMinutes: 6, to: 1)]
        ])

        #expect(direction.branchEndRows == [
            BranchEndRow(end: Self.ends[0], shown: .trains([train(inMinutes: 3, to: 0), train(inMinutes: 9, to: 0)])),
            BranchEndRow(end: Self.ends[1], shown: .trains([train(inMinutes: 6, to: 1)]))
        ])
    }

    @Test func saysThatAnEndThatPRIMDoesNotListHasNoTrainListedWhileTheOtherEndHasTrains() {
        let direction = north([[train(inMinutes: 3, to: 0), train(inMinutes: 5, to: 0)], []])

        #expect(direction.branchEndRows?.map(\.shown) == [
            .trains([train(inMinutes: 3, to: 0), train(inMinutes: 5, to: 0)]),
            .notListed
        ])
    }

    @Test func saysOverAnHourForAnEndWhoseLaterTrainIsKnown() {
        let direction = north([[train(inMinutes: 3, to: 0)], []], overAnHour: [false, true])

        #expect(direction.branchEndRows?.map(\.shown) == [.trains([train(inMinutes: 3, to: 0)]), .overAnHour])
    }

    @Test func saysNoTrainForBothEndsOnlyWhenTheDirectionListsNoTrainAtAll() {
        let direction = north([[], []])

        #expect(direction.branchEndRows?.map(\.shown) == [.noTrain, .noTrain])
    }

    @Test func saysOverAnHourForEachEndWhenTheDirectionHasOnlyLaterTrains() {
        let direction = north([[], []], overAnHour: [true, true], directionOverAnHour: true)

        #expect(direction.branchEndRows?.map(\.shown) == [.overAnHour, .overAnHour])
    }

    @Test func hasNoEndRowsForADirectionWithOneEnd() {
        let direction = LineDirection(label: "Châtillon - Montrouge", times: [now.addingTimeInterval(120)])

        #expect(direction.branchEndRows == nil)
    }
}
