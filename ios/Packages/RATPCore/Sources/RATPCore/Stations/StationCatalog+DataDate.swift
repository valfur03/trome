import Foundation

extension StationCatalog {
    public static var dataDateStyle: Date.FormatStyle {
        var style = Date.FormatStyle(date: .long, time: .omitted)
        style.timeZone = .gmt
        return style
    }

    static func dataDate(from text: String) throws -> Date {
        try Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day().parse(text)
    }
}
