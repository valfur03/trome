import Foundation
@testable import TROMECore

@MainActor
final class StubLocationPermission: LocationPermission {
    var authorization: LocationAuthorization = .authorized
    var isAskingAlways = false
    private var alwaysQuestionWaiters: [CheckedContinuation<Void, Never>] = []

    var isWaitingForAlwaysQuestion: Bool {
        !alwaysQuestionWaiters.isEmpty
    }

    func requestAuthorization() async -> LocationAuthorization {
        authorization
    }

    func waitForAlwaysQuestion() async {
        guard isAskingAlways else { return }
        await withCheckedContinuation { alwaysQuestionWaiters.append($0) }
    }

    func answerAlwaysQuestion() {
        isAskingAlways = false
        alwaysQuestionWaiters.forEach { $0.resume() }
        alwaysQuestionWaiters = []
    }
}
