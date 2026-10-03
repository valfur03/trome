import TROMECore
import SwiftUI

struct LiveActivityStateSection: View {
    @Environment(StationLiveActivityModel.self) private var liveActivity
    @Environment(AutoLiveActivityModel.self) private var autoLiveActivity

    var body: some View {
        Section {
            if liveActivity.isShowing, let station = autoLiveActivity.shownStation {
                Text("On the lock screen: \(station.name)")
                    .accessibilityIdentifier("liveActivityStationName")
            } else {
                Text("The Live Activity shows the next trains of the station nearest to you on your lock screen.")
                    .accessibilityIdentifier("liveActivityExplanation")
            }
            LiveActivityStartError()
        }
    }
}
