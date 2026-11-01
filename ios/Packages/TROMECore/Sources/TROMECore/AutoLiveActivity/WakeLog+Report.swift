import Foundation

extension WakeLog {
    /// The text that the Wake log shares, newest line first: the settings of the phone, then each line with its time
    /// and kind. It holds what the lines hold, never a coordinate: the wake lines give a distance to a station,
    /// with no direction.
    public func report(phone: [String]) -> String {
        (phone + [""] + entries.map { "\(Self.time(of: $0)) [\($0.kind.rawValue)] \($0.text)" })
            .joined(separator: "\n")
    }

    public static func time(of entry: WakeLogEntry) -> String {
        entry.date.formatted(.dateTime.day().month(.abbreviated).hour().minute().second())
    }
}
