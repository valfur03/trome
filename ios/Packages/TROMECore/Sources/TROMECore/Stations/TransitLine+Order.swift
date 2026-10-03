import Foundation

extension TransitLine {
    static func stationListOrder(_ first: TransitLine, _ second: TransitLine) -> Bool {
        (first.modeRank, first.number, first.name) < (second.modeRank, second.number, second.name)
    }

    private var modeRank: Int {
        mode == .metro ? 0 : 1
    }

    private var number: Int {
        Int(name.filter(\.isNumber)) ?? 0
    }
}
