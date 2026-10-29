import Foundation

public struct LiveActivityRemoval: Equatable, Sendable {
    public var endedByTheApp: Bool
    public var activitiesAreEnabled: Bool

    public init(endedByTheApp: Bool, activitiesAreEnabled: Bool) {
        self.endedByTheApp = endedByTheApp
        self.activitiesAreEnabled = activitiesAreEnabled
    }
}

@MainActor
public protocol LiveActivityWatcher: AnyObject {
    func watchRemovals(_ onRemoval: @escaping @MainActor (LiveActivityRemoval) -> Void)
    /// Each Live Activity that iOS shows and that the app did not start, such as one that the server's push started.
    func watchAppearances(_ onAppearance: @escaping @MainActor () -> Void)
}
