import Foundation

enum HTTPDate {
    static func lastModified(of response: HTTPURLResponse) -> Date? {
        response.value(forHTTPHeaderField: "Last-Modified").flatMap(parse)
    }

    static func parse(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.date(from: text)
    }
}
