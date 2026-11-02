import Foundation

public struct LiveActivityRemoval: Equatable, Sendable {
    public var endedByTheApp: Bool
    public var activitiesAreEnabled: Bool

    public init(endedByTheApp: Bool, activitiesAreEnabled: Bool) {
        self.endedByTheApp = endedByTheApp
        self.activitiesAreEnabled = activitiesAreEnabled
    }
}

/// The state that iOS gives a Live Activity that it no longer runs: its only word on why it ended.
/// `dismissed`: a person or iOS removed it from the screen (a swipe of the rider); `ended`: it stays on the
/// screen but no longer updates (an end by iOS).
public enum LiveActivityEndState: String, Equatable, Sendable {
    case ended
    case dismissed
}

@MainActor
public protocol LiveActivityWatcher: AnyObject {
    /// The end state of the last Live Activity that iOS showed, read when the app finds it gone, or nil when iOS
    /// does not say: the wake log names with it who ended a Live Activity outside the app.
    var endState: LiveActivityEndState? { get }
    func watchRemovals(_ onRemoval: @escaping @MainActor (LiveActivityRemoval) -> Void)
    /// Each Live Activity that iOS shows and that the app did not start, such as one that the server's push started.
    func watchAppearances(_ onAppearance: @escaping @MainActor () -> Void)
}
