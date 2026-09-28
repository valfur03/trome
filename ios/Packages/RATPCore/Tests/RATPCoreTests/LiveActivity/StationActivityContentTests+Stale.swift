import Foundation
import Testing
@testable import RATPCore

extension StationActivityContentTests {
    @Test func becomesStaleWhenTheSoonestTrainOfAnyLineLeaves() {
        let trains = board([
            train(line12, to: "Mairie d'Issy", inMinutes: 3, from: southQuay),
            train(line2, to: "Nation", inMinutes: 2, from: "STIF:StopPoint:Q:3:")
        ])

        let content = ContentState(station: station, trains: trains, now: now, firstLineIndex: 1)

        #expect(lines(of: content).map(\.line.name) == ["12"])
        #expect(content.staleDate == time(inMinutes: 2))
    }

    @Test func neverBecomesStaleWhenNoDirectionHasATrain() {
        let trains = board([train(line12, to: "Mairie d'Issy", inMinutes: -0.25, from: southQuay)])

        #expect(ContentState(station: station, trains: trains, now: now).staleDate == nil)
    }

    @Test func becomesStaleWhenTheTrainsTakeTooLongToLoad() {
        let content = ContentState(station: station, trains: .loading, now: now)

        #expect(content.staleDate == now.addingTimeInterval(ContentState.loadingTimeout))
    }

    @Test func neverBecomesStaleWithoutTrainTimes() {
        #expect(ContentState(station: station, trains: .noLiveData, now: now).staleDate == nil)
    }
}
