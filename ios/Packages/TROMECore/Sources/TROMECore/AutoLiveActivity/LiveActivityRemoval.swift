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
public protocol LiveActivityRemovalWatcher: AnyObject {
    func watchRemovals(_ onRemoval: @escaping @MainActor (LiveActivityRemoval) -> Void)
}
