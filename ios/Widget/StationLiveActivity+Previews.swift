import RATPCore
import SwiftUI
import WidgetKit

#Preview("Lock screen", as: .content, using: StationActivityAttributes()) {
    StationLiveActivity()
} contentStates: {
    StationActivityAttributes.ContentState.preview(stationName: "Abbesses", lines: [
        LineTrains(line: TransitLine(mode: .metro, name: "12"), directions: [
            LineDirection(
                label: "Mairie d'Aubervilliers",
                times: [.now.addingTimeInterval(180), .now.addingTimeInterval(540)]
            ),
            LineDirection(label: "Mairie d'Issy", times: [.now.addingTimeInterval(60)])
        ])
    ])
    StationActivityAttributes.ContentState.preview(stationName: "Place de Clichy", lines: [
        LineTrains(line: TransitLine(mode: .metro, name: "13"), directions: [
            LineDirection(label: "Saint-Denis - Université / Asnières - Gennevilliers - Les Courtilles", trains: [
                LineDirection.Train(
                    time: .now.addingTimeInterval(60),
                    destination: "Asnières - Gennevilliers - Les Courtilles"
                ),
                LineDirection.Train(time: .now.addingTimeInterval(300), destination: "Saint-Denis - Université")
            ]),
            LineDirection(label: "Châtillon - Montrouge", times: [.now.addingTimeInterval(120)])
        ])
    ])
    StationActivityAttributes.ContentState.preview(
        stationName: "Châtelet",
        lines: [
            LineTrains(line: TransitLine(mode: .metro, name: "1"), directions: [
                LineDirection(label: "La Défense", times: [.now.addingTimeInterval(120)]),
                LineDirection(label: "Château de Vincennes", times: [.now.addingTimeInterval(60)])
            ]),
            LineTrains(line: TransitLine(mode: .metro, name: "4"), directions: [
                LineDirection(label: "Porte de Clignancourt", times: [.now.addingTimeInterval(240)]),
                LineDirection(label: "Bagneux - Lucie Aubrac", times: [])
            ])
        ],
        otherLines: ["7", "11", "14"].map { TransitLine(mode: .metro, name: $0) }
            + ["A", "B", "D"].map { TransitLine(mode: .rer, name: $0) }
    )
    StationActivityAttributes.ContentState.preview(
        stationName: "Châtelet - Les Halles",
        lines: [
            LineTrains(line: TransitLine(mode: .metro, name: "1"), directions: [
                LineDirection(label: "La Défense", times: [.now.addingTimeInterval(180)]),
                LineDirection(label: "Château de Vincennes", times: [.now.addingTimeInterval(300)])
            ]),
            LineTrains(line: TransitLine(mode: .metro, name: "4"), directions: [
                LineDirection(label: "Porte de Clignancourt", times: [.now.addingTimeInterval(120)]),
                LineDirection(label: "Bagneux - Lucie Aubrac", times: [.now.addingTimeInterval(240)])
            ])
        ],
        otherLines: ["7", "11", "14"].map { TransitLine(mode: .metro, name: $0) }
            + ["A", "B", "D"].map { TransitLine(mode: .rer, name: $0) }
    )
    StationActivityAttributes.ContentState(stationName: "Abbesses", trains: .noData, updatedAt: .now)
}

private extension StationActivityAttributes.ContentState {
    static func preview(
        stationName: String,
        lines: [LineTrains],
        otherLines: [TransitLine] = []
    ) -> Self {
        let soonest = lines
            .flatMap { line in
                line.directions.compactMap(\.times.first).map { SoonestTrain(line: line.line, time: $0) }
            }
            .min { $0.time < $1.time }
        return Self(
            stationName: stationName,
            trains: .lines(LinesPage(
                lines: lines,
                allLines: lines.map(\.line) + otherLines,
                firstIndex: 0,
                soonestTrain: soonest
            )),
            updatedAt: .now
        )
    }
}
