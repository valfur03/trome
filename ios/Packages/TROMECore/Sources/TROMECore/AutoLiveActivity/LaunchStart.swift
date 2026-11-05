import Foundation

/// How a launch began, told from the only facts that iOS gives the app: whether a screen of the app came to the front,
/// and how long after the launch. The state of the app at launch tells nothing: iOS reports it in the background
/// before the screen of a tap comes, so a tap and a wake look alike there.
/// A screen within `openWindow` of the launch is the rider opening the app; none by then is iOS running it, which a
/// later screen follows when the rider opens it after the wake. Each launch writes at most two of these lines.
struct LaunchStart {
    static let openWindow: TimeInterval = 5
    static let unknownLine = """
        How the previous launch began: unknown, the app stopped or was suspended within \(Int(openWindow)) s, \
        with no screen in front
        """
    static let noScreenLine = "iOS ran the app: no screen of the app came to the front in its first \(Int(openWindow)) s"

    private enum State {
        case waiting
        case ranWithNoScreen
        case opened
    }

    private var state = State.waiting

    /// Whether this launch has written its first line yet: the next launch tells it as unknown when it has not.
    var isPending: Bool { state == .waiting }

    /// The lines of a screen of the app that comes to the front, `delay` after the launch.
    mutating func screenCameToFront(after delay: TimeInterval) -> [String] {
        switch state {
        case .opened:
            return []
        case .ranWithNoScreen:
            state = .opened
            return [Self.openedAfterWake(delay)]
        case .waiting where delay <= Self.openWindow:
            state = .opened
            return ["Opened by the rider: on screen \(String(format: "%.1f", max(0, delay))) s after the launch"]
        case .waiting:
            // The end of the window did not run in time, as iOS suspended the app: no screen came in it either.
            state = .opened
            return [Self.noScreenLine, Self.openedAfterWake(delay)]
        }
    }

    /// The line of the end of `openWindow`, when no screen came in it.
    mutating func openWindowEnded() -> [String] {
        guard state == .waiting else { return [] }
        state = .ranWithNoScreen
        return [Self.noScreenLine]
    }

    private static func openedAfterWake(_ delay: TimeInterval) -> String {
        "Opened by the rider \(WakeProcess.duration(delay)) after iOS ran the app"
    }
}
