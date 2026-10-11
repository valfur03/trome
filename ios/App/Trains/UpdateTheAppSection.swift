import TROMECore
import SwiftUI

/// Shows when the server refused the app token of this build: only an update of the app brings the times back.
struct UpdateTheAppSection: View {
    @Environment(StationLiveActivityModel.self) private var liveActivity

    var body: some View {
        if liveActivity.appNeedsUpdate {
            NightCard(isProblem: true) {
                Label {
                    Text("Update the app")
                        .font(.subheadline.weight(.semibold))
                } icon: {
                    Image(systemName: "arrow.down.app.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Update the app to get the times."))
                .accessibilityIdentifier("updateTheAppNotice")
            }
        }
    }
}
