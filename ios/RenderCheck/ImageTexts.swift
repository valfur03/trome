import CoreGraphics
import RATPCore

struct ExpectedText: Encodable {
    enum Kind: String, Encodable {
        case station
        case label
        case destination
    }

    let kind: Kind
    let text: String
    var line: Int?
    var direction: Int?

    static func all(of state: StationActivityAttributes.ContentState) -> [ExpectedText] {
        var texts = [ExpectedText(kind: .station, text: state.stationName)]
        for (lineIndex, line) in (state.trains.linesPage?.lines ?? []).enumerated() {
            if let stationName = line.stationName {
                texts.append(ExpectedText(kind: .label, text: stationName, line: lineIndex))
            }
            for (directionIndex, direction) in line.directions.enumerated() {
                let names = [direction.label, direction.name] + direction.trains.map(\.destination)
                for name in names.reduce(into: [String](), { if !$0.contains($1) { $0.append($1) } }) {
                    texts.append(
                        ExpectedText(kind: .destination, text: name, line: lineIndex, direction: directionIndex)
                    )
                }
            }
        }
        return texts
    }
}

struct ImageTexts: Encodable {
    let image: String
    let station: String
    let page: Int
    let isStale: Bool
    let surface: String
    let size: String
    let height: CGFloat
    let drawn: [DrawnText]
    let expected: [ExpectedText]
}
