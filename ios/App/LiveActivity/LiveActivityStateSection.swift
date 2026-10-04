import TROMECore
import SwiftUI

struct LiveActivityStateSection: View {
    @Environment(StationLiveActivityModel.self) private var liveActivity
    @Environment(AutoLiveActivityModel.self) private var autoLiveActivity

    var body: some View {
        NightPlate(isProblem: autoLiveActivity.liveActivityProblem != nil) {
            if liveActivity.isShowing, let station = autoLiveActivity.shownStation {
                HStack(alignment: .top, spacing: 10) {
                    StationLineBadges(lines: station.lines)
                    Spacer(minLength: 0)
                    Circle()
                        .fill(NightLook.showingDot)
                        .frame(width: 10, height: 10)
                        .padding(.top, 6)
                        .accessibilityHidden(true)
                }
                Text("On the lock screen: \(station.name)")
                    .font(.title2.bold())
                    .accessibilityIdentifier("liveActivityStationName")
            } else if liveActivity.isShowing, autoLiveActivity.showsExample,
                      let station = autoLiveActivity.exampleStation {
                Text("On the lock screen: \(station.name) (example)")
                    .accessibilityIdentifier("liveActivityStationName")
            } else {
                Label {
                    Text("The Live Activity shows the next trains of the station nearest to you on your lock screen.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .accessibilityIdentifier("liveActivityExplanation")
                } icon: {
                    Image(systemName: "lock.iphone")
                        .font(.title3.weight(.semibold))
                }
            }
            ExampleRow()
            LiveActivityStartError()
        }
    }
}
