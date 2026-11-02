import Foundation

extension WakeLog {
    /// The record keeps the newest groups of PRIM entries up to this number: a group of a pair is about 2 KB.
    public static let maximumPRIMGroups = 20
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
            record(.prim, group.text, keepingAtMost: Self.maximumPRIMGroups)
        }
    }
}
