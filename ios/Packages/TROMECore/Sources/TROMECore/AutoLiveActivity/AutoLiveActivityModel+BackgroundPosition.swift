import Foundation

/// When the app follows the position away from the screen. It does only for a Live Activity that shows (to switch
/// or end it), and while it decides an arrival that iOS reported for the area of a station (the second chance and
/// the ask to the server included). Otherwise iOS ran the app for each new position for nothing, and drained the
/// battery of a rider who only opened the app once.
extension AutoLiveActivityModel {
    /// The keeper keeps the app running in the background, and the position stream feeds the rules.
    func followPositionInBackground() {
        isKeepingAwake = true
        services.locationKeeper.begin()
        guard inputs.permission.authorization == .authorized else { return }
        inputs.locationService.start(for: .backgroundWork)
    }

    func stopFollowingPositionInBackground() {
        let wasKeepingAwake = isKeepingAwake
        isKeepingAwake = false
        services.locationKeeper.end()
        inputs.locationService.stop(for: .backgroundWork)
        if wasKeepingAwake {
            logRegionHoldLater()
        }
    }
}
