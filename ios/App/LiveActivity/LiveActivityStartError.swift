import TROMECore
import SwiftUI
import UIKit

struct LiveActivityStartError: View {
    @Environment(AutoLiveActivityModel.self) private var autoLiveActivity
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let error = autoLiveActivity.liveActivityProblem {
            Label {
                Text(message(for: error))
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("liveActivityError")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white, NightLook.problem)
                    .accessibilityHidden(true)
            }
            if error == .turnedOff {
                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
                .buttonStyle(.problem)
                .accessibilityIdentifier("liveActivitySettingsButton")
            }
        }
    }

    private func message(for error: StationLiveActivityError) -> LocalizedStringKey {
        switch error {
        case .turnedOff:
            "Live Activities are off"
        case .failed:
            "The lock screen display could not start."
        }
    }
}
