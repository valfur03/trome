import Foundation
import Testing
@testable import RATPCore

extension StationActivityContentTests {
    @Test func dropsTimesMoreThanAnHourAwayAndSaysTheNextTrainIsOverAnHourAwayForADirectionLeftEmpty() {
        let trains = board([
            train(line12, to: "Mairie d'Issy", inMinutes: 154, from: southQuay),
            train(line12, to: "Mairie d'Issy", inMinutes: 8, from: southQuay),
            train(line12, to: "Mairie d'Aubervilliers", inMinutes: 75, from: northQuay)
        ])

        let content = ContentState(station: station, trains: trains, now: now)

        #expect(linesOfEveryPage(at: station, trains: trains)[1].directions == [
            LineDirection(label: "Mairie d'Aubervilliers", times: [], nextTrainIsOverAnHourAway: true),
            LineDirection(label: "Mairie d'Issy", times: [time(inMinutes: 8)])
        ])
        #expect(content.staleDate == time(inMinutes: 8))
    }

    @Test func saysTheNextTrainIsOverAnHourAwayAtTheEndOfAnHourlyLineRightAfterATrainLeaves() {
        let rerC = TransitLine(mode: .rer, name: "C", stopIds: ["IDFM:monomodalStopPlace:47115"])
        let saintMartin = Station(
            id: "IDFM:monomodalStopPlace:47115",
            name: "Saint-Martin d'Étampes",
            coordinate: Coordinate(48.427488, 2.145259),
            lines: [rerC]
        )
        let trains = board([
            train(rerC, to: "Saint-Martin d'Étampes", inMinutes: -2, from: nil),
            train(rerC, to: "Versailles Château Rive Gauche", inMinutes: -0.75, from: nil),
            train(rerC, to: "Versailles Château Rive Gauche", inMinutes: 63, from: nil)
        ], at: [saintMartin])

        let content = ContentState(station: saintMartin, trains: trains, now: now)

        #expect(lines(of: content).map(\.directions.count) == [1])
        #expect(lines(of: content)[0].directions[0].nextTrainIsOverAnHourAway)
        #expect(lines(of: content)[0].directions[0].times.isEmpty)
        #expect(content.trains.linesPage?.nextTrainIsOverAnHourAway == true)
        #expect(content.staleDate == time(inMinutes: 3))
    }

    @Test func becomesStaleWhenTheFirstTrainMoreThanAnHourAwayComesWithinTheHour() {
        let trains = board([
            train(line12, to: "Mairie d'Issy", inMinutes: 75, from: southQuay),
            train(line2, to: "Nation", inMinutes: 64, from: "STIF:StopPoint:Q:3:")
        ])

        let content = ContentState(station: station, trains: trains, now: now)

        #expect(content.trains.linesPage?.nextTrainIsOverAnHourAway == true)
        #expect(content.staleDate == time(inMinutes: 4))
    }
}
