import CoreLocation
import TROMECore
import UIKit

@MainActor
final class CoreLocationPermission: NSObject, LocationPermission {
    var onAccessChange: (() -> Void)?

    private let manager = CLLocationManager()
    private var questions = LocationQuestionsRules()
    private var authorizationWaiters: [CheckedContinuation<LocationAuthorization, Never>] = []
    private var alwaysQuestionWaiters: [CheckedContinuation<Void, Never>] = []
    private var appObservers: [NSObjectProtocol] = []
    private var alwaysQuestionTimeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        observeApp(UIApplication.didBecomeActiveNotification, as: .appBecameActive)
        observeApp(UIApplication.willResignActiveNotification, as: .appResignedActive)
        observeApp(UIApplication.didEnterBackgroundNotification, as: .appEnteredBackground)
    }

    var authorization: LocationAuthorization {
        Self.authorization(from: manager.authorizationStatus)
    }

    var access: LocationAccess {
        switch manager.authorizationStatus {
        case .notDetermined: .notDecided
        case .authorizedAlways: .always
        case .authorizedWhenInUse: .whileUsing
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }

    func requestAuthorization() async -> LocationAuthorization {
        guard authorization == .notDetermined else { return authorization }
        return await withCheckedContinuation { continuation in
            authorizationWaiters.append(continuation)
            perform(questions.start(access: access))
        }
    }

    func waitForAlwaysQuestion() async {
        guard questions.isAsking else { return }
        await withCheckedContinuation { continuation in
            alwaysQuestionWaiters.append(continuation)
        }
    }

    private func observeApp(_ name: Notification.Name, as event: LocationQuestionsRules.Event) {
        let center = NotificationCenter.default
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
        }
        appObservers.append(observer)
    }

    private func authorizationDidChange() {
        onAccessChange?()
        let appIsActive = UIApplication.shared.applicationState == .active
        handle(.accessChanged(access, appIsActive: appIsActive))
    }

    private func handle(_ event: LocationQuestionsRules.Event) {
        perform(questions.handle(event))
    }

    private func perform(_ action: LocationQuestionsRules.Action?) {
        switch action {
        case .askWhileUsing:
            manager.requestWhenInUseAuthorization()
        case .askAlways:
            manager.requestAlwaysAuthorization()
            startAlwaysQuestionTimeout()
        case nil:
            break
        }
        if !questions.keepsAuthorizationRequestsWaiting {
            resumeAuthorizationWaiters()
        }
        if !questions.isAskingAlways {
            alwaysQuestionTimeoutTask?.cancel()
            alwaysQuestionTimeoutTask = nil
        }
        if !questions.isAsking {
            resumeAlwaysQuestionWaiters()
        }
    }

    private func startAlwaysQuestionTimeout() {
        alwaysQuestionTimeoutTask?.cancel()
        alwaysQuestionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: LocationQuestionsRules.alwaysQuestionTimeout)
            guard !Task.isCancelled else { return }
            self?.handle(.alwaysQuestionTimedOut)
        }
    }

    private func resumeAuthorizationWaiters() {
        let current = authorization
        let waiters = authorizationWaiters
        authorizationWaiters = []
        waiters.forEach { $0.resume(returning: current) }
    }

    private func resumeAlwaysQuestionWaiters() {
        let waiters = alwaysQuestionWaiters
        alwaysQuestionWaiters = []
        waiters.forEach { $0.resume() }
    }

    private static func authorization(from status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }
}

extension CoreLocationPermission: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            authorizationDidChange()
        }
    }
}
