import TROMECore
import SwiftUI
import WidgetKit

#Preview("Lock screen", as: .content, using: StationActivityAttributes()) {
    StationLiveActivity()
} contentStates: {
    StationActivityAttributes.ContentState.preview(stationName: "Abbesses", lines: [
        LineTrains(line: .metro("12", "00643c", "ffffff"), directions: [
            LineDirection(
                label: "Mairie d'Aubervilliers",
                times: [.now.addingTimeInterval(180), .now.addingTimeInterval(540)]
            ),
            LineDirection(label: "Mairie d'Issy", trains: [
                LineDirection.Train(
                    time: .now.addingTimeInterval(40),
                    destination: "Mairie d'Issy",
                    status: .approaching
                ),
                LineDirection.Train(time: .now.addingTimeInterval(420), destination: "Mairie d'Issy")
            ])
        ])
    ])
    StationActivityAttributes.ContentState.preview(stationName: "Place de Clichy", lines: [
        LineTrains(line: .metro("13", "82c8e6", "000000"), directions: [
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
    StationActivityAttributes.ContentState.preview(stationName: "Boigneville", lines: [
        LineTrains(line: TransitLine(mode: .rer, name: "D"), directions: [
            LineDirection(label: "Creil", times: [.now.addingTimeInterval(720), .now.addingTimeInterval(2520)]),
            LineDirection(label: "Malesherbes", times: [], nextTrainIsOverAnHourAway: true)
        ])
    ])
    StationActivityAttributes.ContentState.preview(
        stationName: "Châtelet",
        lines: [
            LineTrains(line: .metro("1", "ffbe00", "000000"), directions: [
                LineDirection(label: "La Défense", times: [.now.addingTimeInterval(120)]),
                LineDirection(label: "Château de Vincennes", times: [.now.addingTimeInterval(60)])
            ]),
            LineTrains(line: .metro("4", "a0006e", "ffffff"), directions: [
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
            LineTrains(line: .metro("1", "ffbe00", "000000"), directions: [
                LineDirection(label: "La Défense", times: [.now.addingTimeInterval(180)]),
                LineDirection(label: "Château de Vincennes", times: [.now.addingTimeInterval(300)])
            ]),
            LineTrains(line: .metro("4", "a0006e", "ffffff"), directions: [
                LineDirection(label: "Porte de Clignancourt", times: [.now.addingTimeInterval(120)]),
                LineDirection(label: "Bagneux - Lucie Aubrac", times: [.now.addingTimeInterval(240)])
            ])
        ],
        otherLines: ["7", "11", "14"].map { TransitLine(mode: .metro, name: $0) }
            + ["A", "B", "D"].map { TransitLine(mode: .rer, name: $0) }
    )
    StationActivityAttributes.ContentState.preview(
        stationName: "Opéra",
        lines: [
            LineTrains(line: TransitLine(mode: .metro, name: "8"), directions: [
                LineDirection(label: "Balard", times: [.now.addingTimeInterval(120)]),
                LineDirection(label: "Pointe du Lac", times: [.now.addingTimeInterval(240)])
            ]),
            LineTrains(
                line: TransitLine(mode: .metro, name: "13"),
                directions: [
                    LineDirection(label: "Châtillon - Montrouge", times: [.now.addingTimeInterval(60)])
                ],
                stationName: "Saint-Lazare"
            )
        ],
        otherLines: ["9", "12", "14"].map { TransitLine(mode: .metro, name: $0) }
            + ["A", "E"].map { TransitLine(mode: .rer, name: $0) }
    )
    StationActivityAttributes.ContentState(stationName: "Abbesses", trains: .noData, updatedAt: .now)
    StationActivityAttributes.ContentState(stationName: "Abbesses", trains: .noData, updatedAt: .now, serverIsOut: true)
    StationActivityAttributes.ContentState(
        stationName: "Abbesses", trains: .noData, updatedAt: .now, appNeedsUpdate: true
    )
}

private extension TransitLine {
    static func metro(_ name: String, _ color: String, _ text: String) -> TransitLine {
        TransitLine(mode: .metro, name: name, color: LineColor(background: color, text: text))
    }
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
