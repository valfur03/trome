#if DEBUG
import CoreLocation
import TROMECore

// The E2E tests end the location work of the app before they kill it. When the app is killed while it streams
// positions, locationd keeps the stream and starts the app again in the background to serve it, at a time that no
// test controls; the next launch can then fail with "No such process". The app cannot end the stream as it dies:
// the end never leaves the app before its exit. So the tests post `end` (a Darwin notification); the app ends its
// background sessions and its position stream, then posts `ended` once locationd has answered a request sent
// after the end. iOS has no call that tells whether locationd still keeps a stream of the app.
@MainActor
enum UITestLocationEnd {
    static let endSignal = "TROME.UITests.location.end"
    static let endedSignal = "TROME.UITests.location.ended"
    private static weak var locationService: LocationService?

    static func listen(stopping locationService: LocationService) {
        self.locationService = locationService
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                Task { @MainActor in await UITestLocationEnd.end() }
            },
            endSignal as CFString,
            nil,
            .deliverImmediately
        )
    }

    private static func end() async {
        CoreLocationBackgroundLocationKeeper.log("end for the UI tests")
        CoreLocationBackgroundLocationKeeper.endAllForUITests()
        locationService?.stop()
        await waitUntilLocationdAnswers()
        CoreLocationBackgroundLocationKeeper.log("ended for the UI tests")
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(endedSignal as CFString),
            nil,
            nil,
            true
        )
    }

    // The stream of this request ends with the loop, and locationd keeps nothing of it.
    private static func waitUntilLocationdAnswers() async {
        do {
            for try await _ in CLLocationUpdate.liveUpdates() {
                return
            }
        } catch {
            CoreLocationBackgroundLocationKeeper.log("the location updates failed: \(error)")
        }
    }
}
#endif
