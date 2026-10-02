import Foundation
import Testing
@testable import RATPCore

extension LinesPageTests {
    private func page(_ lines: [LineTrains], soonestIn seconds: TimeInterval? = nil) -> LinesPage {
        LinesPage(
            lines: lines,
            allLines: lines.map(\.line),
            firstIndex: 0,
            soonestTrain: seconds.map { SoonestTrain(line: lines[0].line, time: now.addingTimeInterval($0)) }
        )
    }

    private func train(leavesIn departure: TimeInterval, arrivesIn arrival: TimeInterval?) -> LineDirection.Train {
        LineDirection.Train(
            time: now.addingTimeInterval(departure),
            destination: "Mairie d'Issy",
            arrivalTime: arrival.map { now.addingTimeInterval($0) }
        )
    }

    private func lineTrains(_ mode: TransitMode, _ trains: [LineDirection.Train]) -> LineTrains {
        LineTrains(
            line: TransitLine(mode: mode, name: mode == .metro ? "12" : "B"),
            directions: [LineDirection(label: "End", trains: trains)]
        )
    }

    @Test func redrawsAMetroLineWhenItsNextTrainStartsApproaching() {
        let metro = lineTrains(.metro, [train(leavesIn: 200, arrivesIn: 180), train(leavesIn: 500, arrivesIn: 480)])

        #expect(page([metro]).nextRedrawDate(after: now) == now.addingTimeInterval(121))
    }

    @Test func redrawsAMetroLineWhenItsTrainArrivesThenWhenItLeaves() {
        let metro = lineTrains(.metro, [train(leavesIn: 20, arrivesIn: 10)])

        #expect(page([metro]).nextRedrawDate(after: now) == now.addingTimeInterval(10))
        #expect(page([metro]).nextRedrawDate(after: now.addingTimeInterval(10)) == now.addingTimeInterval(20))
    }

    @Test func redrawsAnRERLineWhenItsNextTrainStartsApproachingThenWhenItLeaves() {
        let rer = lineTrains(.rer, [train(leavesIn: 200, arrivesIn: nil)])

        #expect(page([rer]).nextRedrawDate(after: now) == now.addingTimeInterval(141))
        #expect(page([rer]).nextRedrawDate(after: now.addingTimeInterval(141)) == now.addingTimeInterval(200))
    }

    @Test func redrawsWhenTheSoonestTrainOfALineOffThePageLeaves() {
        let rer = lineTrains(.rer, [train(leavesIn: 200, arrivesIn: nil)])

        #expect(page([rer], soonestIn: 90).nextRedrawDate(after: now) == now.addingTimeInterval(90))
    }

    @Test func redrawsWhenTheSoonestTrainOfAnRERLineOffThePageStartsApproachingArrivesAndLeaves() {
        let metro = lineTrains(.metro, [train(leavesIn: 900, arrivesIn: 880)])
        let rer = lineTrains(.rer, [train(leavesIn: 200, arrivesIn: 180)])

        let page = LinesPage(showing: [metro, rer], from: 0)

        #expect(page.lines.map(\.line.mode) == [.metro])
        #expect(page.nextRedrawDate(after: now) == now.addingTimeInterval(121))
        #expect(page.nextRedrawDate(after: now.addingTimeInterval(121)) == now.addingTimeInterval(180))
        #expect(page.nextRedrawDate(after: now.addingTimeInterval(180)) == now.addingTimeInterval(200))
    }

    @Test func hasNoRedrawWithoutAnUpcomingTrain() {
        let metro = lineTrains(.metro, [train(leavesIn: -10, arrivesIn: -30)])

        #expect(page([metro]).nextRedrawDate(after: now) == nil)
    }

    @Test func redrawsAForkWhenTheSecondTrainOfAnEndArrivesAfterTheTrainsOfTheDirectionLeft() {
        let first = train(leavesIn: 20, arrivesIn: 10)
        let secondOfTheEnd = train(leavesIn: 300, arrivesIn: 280)
        let fork = LineTrains(
            line: TransitLine(mode: .metro, name: "13"),
            directions: [LineDirection(
                label: "Mairie d'Issy",
                trains: [first],
                branchEnds: ["Mairie d'Issy"],
                trainsOfEachEnd: [BranchEndTrains(end: "Mairie d'Issy", trains: [first, secondOfTheEnd])]
            )]
        )

        #expect(page([fork]).nextRedrawDate(after: now.addingTimeInterval(20)) == now.addingTimeInterval(221))
    }
}
