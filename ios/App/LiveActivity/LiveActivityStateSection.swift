import TROMECore
import SwiftUI

struct LiveActivityStateSection: View {
    @Environment(StationLiveActivityModel.self) private var liveActivity
    @Environment(AutoLiveActivityModel.self) private var autoLiveActivity

    var body: some View {
        NightPlate(isProblem: autoLiveActivity.liveActivityProblem != nil) {
            if liveActivity.isShowing, let station = autoLiveActivity.shownStation {
                ShownStationHeader(lines: station.lines)
                Text("On the lock screen: \(station.name)")
                    .font(.title2.bold())
                    .accessibilityIdentifier("liveActivityStationName")
            } else if liveActivity.isShowing, autoLiveActivity.showsExample,
                      let station = autoLiveActivity.exampleStation {
                ShownStationHeader(lines: station.lines)
                Text("On the lock screen: \(station.name) (example)")
                    .font(.title2.bold())
                    .accessibilityIdentifier("liveActivityStationName")
            } else {
                Label {
                    Text("Nothing on the lock screen")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.85))
                        .accessibilityIdentifier("liveActivityNothingShown")
                } icon: {
                    Image(systemName: "lock.iphone")
                        .font(.title3.weight(.semibold))
                }
            }
            LiveActivityStartError()
        }
    }
}

private struct ShownStationHeader: View {
    let lines: [TransitLine]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StationLineBadges(lines: lines)
            Spacer(minLength: 0)
            Circle()
                .fill(NightLook.showingDot)
                .frame(width: 10, height: 10)
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
    }
}
