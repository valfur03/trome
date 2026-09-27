public struct LocationQuestionsRules: Equatable, Sendable {
    public static let alwaysQuestionTimeout: Duration = .seconds(20)

    public enum Event: Equatable, Sendable {
        case accessChanged(LocationAccess, appIsActive: Bool)
        case appBecameActive
        case appResignedActive
        case alwaysQuestionTimedOut
        case appEnteredBackground
    }

    public enum Action: Equatable, Sendable {
        case askWhileUsing
        case askAlways
    }

    enum Step: Equatable, Sendable {
        case idle
        case whileUsingAsked
        case waitingToAskAlways
        case alwaysAsked(appResigned: Bool)
    }

    private(set) var step: Step = .idle

    public var isAsking: Bool {
        step != .idle
    }

    public var isAskingWhileUsing: Bool {
        step == .whileUsingAsked
    }

    public var isAskingAlways: Bool {
        if case .alwaysAsked = step { true } else { false }
    }

    public init() {}

    public mutating func start(access: LocationAccess) -> Action? {
        guard step == .idle, access == .notDecided else { return nil }
        step = .whileUsingAsked
        return .askWhileUsing
    }

    public mutating func handle(_ event: Event) -> Action? {
        switch (step, event) {
        case (.idle, _):
            break
        case (_, .appEnteredBackground):
            step = .idle
        case (.whileUsingAsked, .accessChanged(let access, let appIsActive)):
            return whileUsingAnswered(access, appIsActive: appIsActive)
        case (.waitingToAskAlways, .accessChanged(let access, _)),
             (.alwaysAsked, .accessChanged(let access, _)):
            if access != .whileUsing {
                step = .idle
            }
        case (.waitingToAskAlways, .appBecameActive):
            return askAlways()
        case (.alwaysAsked(appResigned: false), .appResignedActive):
            step = .alwaysAsked(appResigned: true)
        case (.alwaysAsked(appResigned: true), .appBecameActive),
             (.alwaysAsked, .alwaysQuestionTimedOut):
            step = .idle
        default:
            break
        }
        return nil
    }

    private mutating func whileUsingAnswered(_ access: LocationAccess, appIsActive: Bool) -> Action? {
        switch access {
        case .notDecided:
            return nil
        case .whileUsing where appIsActive:
            return askAlways()
        case .whileUsing:
            step = .waitingToAskAlways
            return nil
        case .denied, .always:
            step = .idle
            return nil
        }
    }

    private mutating func askAlways() -> Action {
        step = .alwaysAsked(appResigned: false)
        return .askAlways
    }
}
