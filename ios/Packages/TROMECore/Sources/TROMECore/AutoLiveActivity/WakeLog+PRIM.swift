import Foundation

extension WakeLog {
    /// The record keeps the newest groups of each case of `PRIMWalkRecord` up to this number, each case apart: a
    /// group is about 2 KB. A train that stands at the platform past its time writes about once per station and
    /// hour, on the metro too, so a walk of some hours can fill its bound; a pair (the ghost row) is rare, and
    /// keeps its place among any number of them.
    public static func maximumPRIMGroups(of case: PRIMWalkRecord.Case) -> Int {
        switch `case` {
        case .pair: 20
        case .standing: 20
        }
    }

    /// A case of `PRIMWalkRecord` is written once per station in this time, so that a train that stands at the
    /// platform, or a pair that each refresh gives again, does not write a group at every refresh.
    public static let primGroupSpacing: TimeInterval = 60 * 60

    /// Writes each group whose case and station the record has not written in the last hour.
    public func record(_ groups: [PRIMWalkRecord.Group]) {
        for group in groups {
            let since = now().addingTimeInterval(-Self.primGroupSpacing)
            let isWritten = entries.contains { entry in
                entry.kind == .prim && entry.date > since && entry.text.hasPrefix(group.title + "\n")
            }
            guard !isWritten else { continue }
            record(.prim, group.text, keepingAtMost: Self.maximumPRIMGroups(of: group.case)) { entry in
                entry.text.hasPrefix(group.case.title + ": ")
            }
        }
    }
}
