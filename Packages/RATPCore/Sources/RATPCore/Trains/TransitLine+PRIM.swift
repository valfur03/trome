import Foundation

extension TransitLine {
    private static let primLineCodes: [String: String] = [
        "metro-1": "C01371",
        "metro-2": "C01372",
        "metro-3": "C01373",
        "metro-3bis": "C01386",
        "metro-4": "C01374",
        "metro-5": "C01375",
        "metro-6": "C01376",
        "metro-7": "C01377",
        "metro-7bis": "C01387",
        "metro-8": "C01378",
        "metro-9": "C01379",
        "metro-10": "C01380",
        "metro-11": "C01381",
        "metro-12": "C01382",
        "metro-13": "C01383",
        "metro-14": "C01384",
        "rer-A": "C01742",
        "rer-B": "C01743",
        "rer-C": "C01727",
        "rer-D": "C01728",
        "rer-E": "C01729"
    ]

    public var primLineCode: String? {
        Self.primLineCodes["\(mode.rawValue)-\(name)"]
    }
}

enum PRIMStopReference {
    private static let stopAreaPrefix = "IDFM:monomodalStopPlace:"
    private static let stopPointPrefix = "IDFM:"

    static func monitoringRef(forStopId stopId: String) -> String? {
        if stopId.hasPrefix(stopAreaPrefix) {
            let code = stopId.dropFirst(stopAreaPrefix.count)
            return code.isEmpty ? nil : "STIF:StopArea:SP:\(code):"
        }
        if stopId.hasPrefix(stopPointPrefix) {
            let code = stopId.dropFirst(stopPointPrefix.count)
            return code.isEmpty || code.contains(":") ? nil : "STIF:StopPoint:Q:\(code):"
        }
        return nil
    }

    static func lineCode(fromLineRef lineRef: String) -> String? {
        lineRef.split(separator: ":").last.map(String.init)
    }
}
