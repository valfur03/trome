#if DEBUG
import SwiftUI

// The E2E tests tap the app right after the Notification Center slides away. iOS keeps the app inactive until its own
// animation ends, and drops a tap that comes then; the Notification Center leaves the screen up to a second before
// the end of that animation on a busy Mac, so its exit is not the sign to wait for. This invisible mark gives the
// tests the sign of iOS itself: it says "active" only once iOS has made the app active.
struct UITestScenePhaseMark: View {
    static let identifier = "uiTestScenePhase"

    let isActive: Bool

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityIdentifier(Self.identifier)
            .accessibilityValue(Text(verbatim: isActive ? "active" : "inactive"))
    }
}
#endif
