import Foundation
import Testing
@testable import TROMECore

extension LinesPageTests {
    private struct PRIMTrain {
        let journey: String
        let destination: String
        let quay: String
        let secondsAway: TimeInterval
    }

    private static let northQuay = "STIF:StopPoint:Q:463066:"
    private static let southQuay = "STIF:StopPoint:Q:22225:"

    private func stripsAtLiege(afterAnAnswerOf trains: [PRIMTrain], at answerTime: Date) throws -> LineTrains {
        let catalog = try StationCatalog.bundled()
        let liege = try #require(catalog.stations.first { $0.name == "Liège" })
        let visits = trains.map { train in
            MonitoredVisit(
                monitoringRef: train.quay,
                lineRef: "STIF:Line::C01383:",
                destinationName: train.destination,
                journeyRef: train.journey,
                time: answerTime.addingTimeInterval(train.secondsAway),
                quayRef: train.quay
            )
        }
        let departures = PRIMDeparturesProvider.departures(from: visits, at: [liege])
        let board = DepartureBoard(departures: departures, stations: [liege], now: answerTime)
        let content = StationActivityAttributes.ContentState(
            station: liege,
            trains: .departures(board, updatedAt: answerTime),
            now: answerTime
        )
        return try #require(content.trains.linesPage?.panamStripsLine)
    }

    @Test func keepsTheMarkOfEachTrainThatStaysInTheNextAnswers() throws {
        let saintDenis = "Saint-Denis-Université"
        let asnieres = "Asnières-Gennevilliers Les Courtilles"
        let chatillon = "Châtillon-Montrouge"
        let answers: [(seconds: TimeInterval, trains: [PRIMTrain])] = [
            (0, [
                PRIMTrain(journey: "M13.A.1", destination: saintDenis, quay: Self.northQuay, secondsAway: 250),
                PRIMTrain(journey: "M13.A.2", destination: asnieres, quay: Self.northQuay, secondsAway: 370),
                PRIMTrain(journey: "M13.R.1", destination: chatillon, quay: Self.southQuay, secondsAway: 240)
            ]),
            (30, [
                PRIMTrain(journey: "M13.A.1", destination: saintDenis, quay: Self.northQuay, secondsAway: 228),
                PRIMTrain(journey: "M13.A.2", destination: asnieres, quay: Self.northQuay, secondsAway: 335),
                PRIMTrain(journey: "M13.R.1", destination: chatillon, quay: Self.southQuay, secondsAway: 215)
            ]),
            (60, [
                PRIMTrain(journey: "M13.A.1", destination: saintDenis, quay: Self.northQuay, secondsAway: 190),
                PRIMTrain(journey: "M13.A.2", destination: asnieres, quay: Self.northQuay, secondsAway: 318),
                PRIMTrain(journey: "M13.R.1", destination: chatillon, quay: Self.southQuay, secondsAway: 182)
            ])
        ]

        for answer in answers {
            let line = try stripsAtLiege(afterAnAnswerOf: answer.trains, at: now.addingTimeInterval(answer.seconds))
            let north = try #require(line.directions.first { $0.branchEnds != nil })

            #expect(north.trains.map(\.destination) == north.branchEnds)
            #expect(north.trains.map(\.time) == answer.trains.prefix(2).map {
                now.addingTimeInterval(answer.seconds + $0.secondsAway)
            })
        }
    }
}
