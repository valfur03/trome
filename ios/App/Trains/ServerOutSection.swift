import TROMECore
import SwiftUI

struct ServerOutSection: View {
    @Environment(StationLiveActivityModel.self) private var liveActivity

    var body: some View {
        if let retryAt = liveActivity.serverRetryAt {
            Section {
                message(LiveTimesComeBack(retryAt: retryAt, now: Date()))
                    .accessibilityIdentifier("serverOutNotice")
            }
        }
    }

    private func message(_ comeBack: LiveTimesComeBack) -> Text {
        switch comeBack {
        case .around(let retryAt):
            let time = retryAt.formatted(date: .omitted, time: .shortened)
            return Text("Many riders are using the app right now. Live times come back around \(time).")
        case .tomorrow:
            return Text("Many riders are using the app right now. Live times come back tomorrow.")
        }
    }
}
