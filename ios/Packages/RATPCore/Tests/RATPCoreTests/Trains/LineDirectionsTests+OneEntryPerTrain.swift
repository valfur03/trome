import Foundation
import Testing
@testable import RATPCore

extension LineDirectionsTests {
    private var metro12: TransitLine {
        TransitLine(mode: .metro, name: "12", stopIds: ["IDFM:22055", "IDFM:463205"])
    }

    private var aubervilliersQuay: String {
        "STIF:StopPoint:Q:22055:"
    }

    private var issyQuay: String {
        "STIF:StopPoint:Q:463205:"
    }

    @Test func showsAMetroTrainThatPRIMListsTwiceOnlyOnceInItsDirection() {
        let result = directions(of: metro12, at: "Lamarck - Caulaincourt", [
            train(metro12, to: "Mairie d'Issy", inMinutes: 2, from: issyQuay),
            train(metro12, to: "Mairie d'Issy", inMinutes: 2.4, from: issyQuay),
            train(metro12, to: "Mairie d'Issy", inMinutes: 7, from: issyQuay),
            train(metro12, to: "Mairie d'Aubervilliers", inMinutes: 4, from: aubervilliersQuay)
        ])

        #expect(result == [
            LineDirection(label: "Mairie d'Aubervilliers", times: [time(inMinutes: 4)]),
            LineDirection(label: "Mairie d'Issy", times: [time(inMinutes: 2), time(inMinutes: 7)])
        ])
    }

    @Test func showsAMetroTrainOnceWhenPRIMListsItWithAndWithoutItsQuay() {
        let result = directions(of: metro12, at: "Lamarck - Caulaincourt", [
            train(metro12, to: "Mairie d'Issy", inMinutes: 3, from: issyQuay),
            train(metro12, to: "Mairie d'Issy", inMinutes: 3.5),
            train(metro12, to: "Mairie d'Aubervilliers", inMinutes: 4, from: aubervilliersQuay)
        ])

        #expect(result == [
            LineDirection(label: "Mairie d'Aubervilliers", times: [time(inMinutes: 4)]),
            LineDirection(label: "Mairie d'Issy", times: [time(inMinutes: 3)])
        ])
    }

    @Test func showsAShortTurnTrainOnceWhenPRIMListsItTwice() {
        let result = directions(of: metro12, at: "Lamarck - Caulaincourt", [
            train(metro12, to: "Montparnasse-Bienvenue", inMinutes: 0.5, from: issyQuay),
            train(metro12, to: "Montparnasse-Bienvenue", inMinutes: 0.8, from: issyQuay),
            train(metro12, to: "Mairie d'Aubervilliers", inMinutes: 4, from: aubervilliersQuay)
        ])

        #expect(result.map(\.times) == [[time(inMinutes: 4)], [time(inMinutes: 0.5)]])
    }

    @Test func keepsTwoMetroTrainsOfADirectionThatLeaveAMinuteApart() {
        let result = directions(of: metro12, at: "Lamarck - Caulaincourt", [
            train(metro12, to: "Mairie d'Issy", inMinutes: 2, from: issyQuay),
            train(metro12, to: "Mairie d'Issy", inMinutes: 3, from: issyQuay)
        ])

        #expect(result.last == LineDirection(
            label: "Mairie d'Issy",
            times: [time(inMinutes: 2), time(inMinutes: 3)]
        ))
    }

    @Test func keepsTwoRERTrainsOfADirectionThatLeaveInTheSameMinute() {
        let result = directions(of: rerB, at: "Châtelet - Les Halles", [
            train(rerB, to: "Aéroport Charles de Gaulle 2 (Terminal 2)", inMinutes: 2, from: "STIF:StopPoint:Q:1:"),
            train(rerB, to: "Mitry - Claye", inMinutes: 2.5, from: "STIF:StopPoint:Q:2:")
        ])

        #expect(result.first?.times == [time(inMinutes: 2), time(inMinutes: 2.5)])
    }
}
