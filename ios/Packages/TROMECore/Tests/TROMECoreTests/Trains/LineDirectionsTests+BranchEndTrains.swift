import Foundation
import Testing
@testable import TROMECore

extension LineDirectionsTests {
    private var line13: TransitLine {
        TransitLine(mode: .metro, name: "13", stopIds: ["IDFM:130", "IDFM:131"])
    }

    private var northQuay: String {
        "STIF:StopPoint:Q:130:"
    }

    private var southQuay: String {
        "STIF:StopPoint:Q:131:"
    }

    private var saintDenis: String {
        "Saint-Denis - Université"
    }

    private var asnieres: String {
        "Asnières - Gennevilliers - Les Courtilles"
    }

    private func toSaintDenis(inMinutes minutes: Double) -> Departure {
        train(line13, to: "Saint-Denis-Université", inMinutes: minutes, from: northQuay)
    }

    private func toAsnieres(inMinutes minutes: Double) -> Departure {
        train(line13, to: "Asnières-Gennevilliers Les Courtilles", inMinutes: minutes, from: northQuay)
    }

    private func toChatillon(inMinutes minutes: Double) -> Departure {
        train(line13, to: "Châtillon-Montrouge", inMinutes: minutes, from: southQuay)
    }

    private func endTrain(_ minutes: Double, to end: String) -> LineDirection.Train {
        LineDirection.Train(time: time(inMinutes: minutes), destination: end)
    }

    private func north(
        at stationName: String = "Liège",
        _ departures: [Departure],
        later: [Departure] = []
    ) throws -> LineDirection {
        let result = LineDirections.directions(
            of: line13,
            at: station(stationName, [line13]),
            from: departures,
            later: later,
            now: now
        )
        return try #require(result.first { $0.branchEnds != nil })
    }

    @Test func givesEachEndItsNextTwoTrainsInTheOrderOfTheEndsOfTheLine() throws {
        let direction = try north([
            toAsnieres(inMinutes: 1),
            toSaintDenis(inMinutes: 3),
            toAsnieres(inMinutes: 5),
            toSaintDenis(inMinutes: 7),
            toAsnieres(inMinutes: 9),
            toSaintDenis(inMinutes: 11)
        ])

        #expect(direction.trainsOfEachEnd == [
            BranchEndTrains(end: saintDenis, trains: [endTrain(3, to: saintDenis), endTrain(7, to: saintDenis)]),
            BranchEndTrains(end: asnieres, trains: [endTrain(1, to: asnieres), endTrain(5, to: asnieres)])
        ])
    }

    @Test func keepsTheFirstTwoTrainsOfTheDirectionByTimeForTheSoonestTrain() throws {
        let direction = try north([
            toSaintDenis(inMinutes: 7),
            toAsnieres(inMinutes: 1),
            toAsnieres(inMinutes: 5),
            toSaintDenis(inMinutes: 3)
        ])

        #expect(direction.trains == [endTrain(1, to: asnieres), endTrain(3, to: saintDenis)])
        #expect(direction.branchEnds == [saintDenis, asnieres])
    }

    @Test func givesAnEndWithOneTrainOnlyThatTrain() throws {
        let direction = try north([toSaintDenis(inMinutes: 2), toAsnieres(inMinutes: 4), toSaintDenis(inMinutes: 8)])

        #expect(direction.trainsOfEachEnd?.map(\.trains) == [
            [endTrain(2, to: saintDenis), endTrain(8, to: saintDenis)],
            [endTrain(4, to: asnieres)]
        ])
    }

    @Test func givesTheOtherEndItsOwnTwoTrainsWhenTheNextTwoTrainsGoToOneEnd() throws {
        let direction = try north([
            toSaintDenis(inMinutes: 1),
            toSaintDenis(inMinutes: 3),
            toAsnieres(inMinutes: 6),
            toSaintDenis(inMinutes: 8),
            toAsnieres(inMinutes: 12)
        ])

        #expect(direction.trains == [endTrain(1, to: saintDenis), endTrain(3, to: saintDenis)])
        #expect(direction.trainsOfEachEnd?.last == BranchEndTrains(
            end: asnieres,
            trains: [endTrain(6, to: asnieres), endTrain(12, to: asnieres)]
        ))
    }

    @Test func saysTheNextTrainOfAnEndIsOverAnHourAwayWhenOnlyALaterTrainGoesThere() throws {
        let direction = try north(
            [toSaintDenis(inMinutes: 2), toSaintDenis(inMinutes: 9)],
            later: [toAsnieres(inMinutes: 64), toSaintDenis(inMinutes: 70)]
        )

        #expect(!direction.nextTrainIsOverAnHourAway)
        #expect(direction.trainsOfEachEnd == [
            BranchEndTrains(end: saintDenis, trains: [endTrain(2, to: saintDenis), endTrain(9, to: saintDenis)]),
            BranchEndTrains(end: asnieres, trains: [], nextTrainIsOverAnHourAway: true)
        ])
    }

    @Test func saysNoTrainIsKnownForAnEndWithNoTrainAtAll() throws {
        let direction = try north(
            [toSaintDenis(inMinutes: 2)],
            later: [toSaintDenis(inMinutes: 70), toChatillon(inMinutes: 65)]
        )

        #expect(direction.trainsOfEachEnd?.last == BranchEndTrains(end: asnieres, trains: []))
    }

    @Test func givesEachEndOfADirectionWithNoTrainInTheHourItsOwnLaterState() throws {
        let direction = try north(
            [toChatillon(inMinutes: 3)],
            later: [toAsnieres(inMinutes: 66)]
        )

        #expect(direction.nextTrainIsOverAnHourAway)
        #expect(direction.trainsOfEachEnd == [
            BranchEndTrains(end: saintDenis, trains: []),
            BranchEndTrains(end: asnieres, trains: [], nextTrainIsOverAnHourAway: true)
        ])
    }

    @Test func givesTheEndsTheStateOfTheDirectionWhenTheLaterTrainEndsBeforeTheFork() throws {
        let direction = try north(
            [toChatillon(inMinutes: 3)],
            later: [train(line13, to: "Saint-Ouen", inMinutes: 66, from: northQuay)]
        )

        #expect(direction.nextTrainIsOverAnHourAway)
        #expect(direction.trainsOfEachEnd?.map(\.nextTrainIsOverAnHourAway) == [true, true])
    }

    @Test(arguments: [[62.0, 70.0], [70.0, 62.0]])
    func saysNoTrainIsKnownForAnEndWhenTheLaterTrainsTellTheOtherEndAndAShortTrip(minutes: [Double]) throws {
        let direction = try north(
            [toChatillon(inMinutes: 3)],
            later: [
                train(line13, to: "Saint-Ouen", inMinutes: minutes[0], from: northQuay),
                toSaintDenis(inMinutes: minutes[1])
            ]
        )

        #expect(direction.nextTrainIsOverAnHourAway)
        #expect(direction.trainsOfEachEnd?.map(\.nextTrainIsOverAnHourAway) == [true, false])
    }

    @Test func countsATrainThatPRIMListsTwiceOnceForTheWholeDirection() throws {
        let direction = try north([
            toSaintDenis(inMinutes: 2),
            toSaintDenis(inMinutes: 2.3),
            toAsnieres(inMinutes: 2.6),
            toAsnieres(inMinutes: 5),
            toSaintDenis(inMinutes: 8)
        ])

        #expect(direction.trains == [endTrain(2, to: saintDenis), endTrain(5, to: asnieres)])
        #expect(direction.trainsOfEachEnd?.map(\.trains) == [
            [endTrain(2, to: saintDenis), endTrain(8, to: saintDenis)],
            [endTrain(5, to: asnieres)]
        ])
    }

    @Test func keepsATrainThatEndsBeforeTheForkOutOfTheRowsOfTheEnds() throws {
        let direction = try north([
            train(line13, to: "Saint-Ouen", inMinutes: 1, from: northQuay),
            toSaintDenis(inMinutes: 4),
            toAsnieres(inMinutes: 6)
        ])

        #expect(direction.trains.map(\.destination) == ["Saint-Ouen", saintDenis])
        #expect(direction.trainsOfEachEnd?.map(\.trains) == [
            [endTrain(4, to: saintDenis)],
            [endTrain(6, to: asnieres)]
        ])
    }

    @Test func keepsThePlainDirectionsAndTheBranchesAsTheyAre() throws {
        let liege = LineDirections.directions(
            of: line13,
            at: station("Liège", [line13]),
            from: [toChatillon(inMinutes: 2), toChatillon(inMinutes: 5), toChatillon(inMinutes: 8)],
            now: now
        )
        let brochant = LineDirections.directions(
            of: line13,
            at: station("Brochant", [line13]),
            from: [toAsnieres(inMinutes: 1), toAsnieres(inMinutes: 4), toAsnieres(inMinutes: 7)],
            now: now
        )

        #expect(liege.last == LineDirection(
            label: "Châtillon - Montrouge",
            times: [time(inMinutes: 2), time(inMinutes: 5)]
        ))
        #expect(brochant.first == LineDirection(label: asnieres, times: [time(inMinutes: 1), time(inMinutes: 4)]))
    }

    @Test func givesNoEndRowsToAnRERDirectionWithSeveralEnds() {
        let result = directions(of: rerB, at: "Châtelet - Les Halles", [
            train(rerB, to: "Aéroport Charles de Gaulle 2 (Terminal 2)", inMinutes: 2, from: "STIF:StopPoint:Q:1:"),
            train(rerB, to: "Mitry - Claye", inMinutes: 4, from: "STIF:StopPoint:Q:1:"),
            train(rerB, to: "Mitry - Claye", inMinutes: 9, from: "STIF:StopPoint:Q:1:")
        ])

        #expect(!result.isEmpty)
        #expect(result.allSatisfy { $0.trainsOfEachEnd == nil && $0.trains.count <= 2 })
    }
}
