import Foundation

/// The build that runs, as its Info.plist names it, so that a walk record says which build was walked.
/// The build writes the commit itself (`ios/scripts/build-commit.sh`): its short hash, with `-dirty` when the folder
/// of the app had changes that were not committed.
public struct AppBuild: Equatable, Sendable {
    public static let commitKey = "TROMECommit"
    static let changesSuffix = "-dirty"

    public let number: String?
    public let commit: String?
    public let hasChangesNotCommitted: Bool

    public init(infoDictionary: [String: Any]?) {
        number = Self.value(infoDictionary?["CFBundleVersion"])
        let written = Self.value(infoDictionary?[Self.commitKey]) ?? ""
        let hasSuffix = written.hasSuffix(Self.changesSuffix)
        let hash = hasSuffix ? String(written.dropLast(Self.changesSuffix.count)) : written
        // A hash of 7 to 40 small hex digits: anything else is told as unknown, never written as it is.
        let isHash = (7...40).contains(hash.count) && hash.allSatisfy { "0123456789abcdef".contains($0) }
        commit = isHash ? hash : nil
        hasChangesNotCommitted = isHash && hasSuffix
    }

    /// For example "build 6, commit 1e2e704, iOS 26.1".
    public func summary(iOSVersion: String) -> String {
        let commitPart = switch (commit, hasChangesNotCommitted) {
        case (let commit?, false): "commit \(commit)"
        case (let commit?, true): "commit \(commit) with changes not committed"
        case (nil, _): "commit unknown"
        }
        return "build \(number ?? "unknown"), \(commitPart), iOS \(iOSVersion)"
    }

    /// A value of the Info.plist, with none for an empty one or a setting that the build did not expand.
    private static func value(_ raw: Any?) -> String? {
        guard let text = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              !text.hasPrefix("$(") else {
            return nil
        }
        return text
    }
}
