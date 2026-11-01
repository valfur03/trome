#if WAKE_LOG
import SwiftUI

/// The way to the Wake log in a Release build for a walk (`TROME_WAKE_LOG = YES`): an icon at the top right of the
/// main screen, with no text on the screen. A store build never compiles it.
struct WakeLogLink: View {
    var body: some View {
        NavigationLink {
            WakeLogScreen()
        } label: {
            Label { Text(verbatim: "Wake log") } icon: { Image(systemName: "list.bullet.rectangle") }
        }
        .accessibilityIdentifier("wakeLog")
    }
}
#endif
