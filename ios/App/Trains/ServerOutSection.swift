import TROMECore
import SwiftUI

struct ServerOutSection: View {
    @Environment(StationLiveActivityModel.self) private var liveActivity

    var body: some View {
        if let retryAt = liveActivity.serverRetryAt {
            NightCard {
                Label {
                    message(LiveTimesComeBack(retryAt: retryAt, now: Date()))
                        .font(.subheadline.weight(.semibold))
                } icon: {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(NightLook.secondaryText)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("serverOutNotice")
            }
        }
    }

    private func message(_ comeBack: LiveTimesComeBack) -> Text {
        switch comeBack {
        case .around(let retryAt):
            let time = retryAt.formatted(date: .omitted, time: .shortened)
            return Text("No live times until around \(time)")
        case .tomorrow:
            return Text("No live times until tomorrow")
        }
    }
}
