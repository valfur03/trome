import Foundation
@testable import TROMECore

@MainActor
final class StubStationLiveActivityClient: StationLiveActivityClient {
    var isShowing = false
    var shownContent: StationActivityAttributes.ContentState?
    var startError: (any Error)?
    var areActivitiesEnabled = true
    var holdsNextUpdate = false
    var holdsNextEnd = false
    private var heldUpdate: CheckedContinuation<Void, Never>?
    private var heldEnd: CheckedContinuation<Void, Never>?
    private(set) var started: [StationActivityAttributes.ContentState] = []
    private(set) var updates: [StationActivityAttributes.ContentState] = []
    private(set) var endCount = 0

    func start(_ content: StationActivityAttributes.ContentState) throws {
        if let startError {
            throw startError
        }
        started.append(content)
        shownContent = content
        isShowing = true
    }

    var isHoldingAnUpdate: Bool {
        heldUpdate != nil
    }

    func update(_ content: StationActivityAttributes.ContentState) async {
        if holdsNextUpdate {
            holdsNextUpdate = false
            await withCheckedContinuation { heldUpdate = $0 }
        }
        updates.append(content)
        shownContent = content
    }

    var isHoldingAnEnd: Bool {
        heldEnd != nil
    }

    func end() async {
        if holdsNextEnd {
            holdsNextEnd = false
            await withCheckedContinuation { heldEnd = $0 }
        }
        endCount += 1
        isShowing = false
    }

    func releaseHeldUpdate() {
        heldUpdate?.resume()
        heldUpdate = nil
    }

    func releaseHeldEnd() {
        heldEnd?.resume()
        heldEnd = nil
    }
}
