import TROMECore
import SwiftUI
import UIKit

struct LiveActivityStartError: View {
    @Environment(AutoLiveActivityModel.self) private var autoLiveActivity
    @Environment(\.appName) private var appName
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let error = autoLiveActivity.liveActivityProblem {
            Text(message(for: error))
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityIdentifier("liveActivityError")
            if error == .turnedOff {
                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
                .accessibilityIdentifier("liveActivitySettingsButton")
            }
        }
    }

    private func message(for error: StationLiveActivityError) -> LocalizedStringKey {
        switch error {
        case .turnedOff:
            "Live Activities are turned off for this app. Turn them on in Settings > \(appName)."
        case .failed:
            "The lock screen display could not start."
        }
    }
}
