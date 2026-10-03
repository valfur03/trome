import TROMECore
import SwiftUI

struct NearestStationLiveActivitySection: View {
    let nearestStationModel: NearestStationModel

    @Environment(StationLiveActivityModel.self) private var liveActivity
    @Environment(AutoLiveActivityModel.self) private var autoLiveActivity
    @State private var isLookingForStation = false
    @State private var problem: NearestStationProblem?

    private var walkingDistance: String {
        Measurement(value: StationCatalog.walkingDistanceMeters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    var body: some View {
        Section {
            VStack(spacing: 12) {
                if liveActivity.isShowing {
                    ShownLiveActivityControls()
                } else {
                    showNearestStationButton
                    if let problem {
                        Text(message(for: problem))
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("nearestStationProblem")
                    }
                }
                LiveActivityStartError()
            }
            .frame(maxWidth: .infinity)
            .onChange(of: liveActivity.isShowing) { problem = nil }
        } footer: {
            Text("The Live Activity shows the next trains of the station nearest to you on your lock screen.")
        }
    }

    private var showNearestStationButton: some View {
        Button {
            Task { await showNearestStation() }
        } label: {
            if isLookingForStation {
                ProgressView("Finding the nearest station…")
                    .frame(maxWidth: .infinity)
            } else {
                ButtonLabel("Show the Live Activity now", systemImage: "lock.iphone")
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .adaptiveButtonBorderShape()
        .disabled(isLookingForStation)
        .accessibilityIdentifier("showNearestStationLiveActivity")
    }

    private func showNearestStation() async {
        problem = nil
        isLookingForStation = true
        defer { isLookingForStation = false }
        switch await nearestStationModel.nearestStationNow() {
        case .success(let station):
            await autoLiveActivity.startByHand(station)
        case .failure(let failure):
            problem = failure
        }
    }

    private func message(for problem: NearestStationProblem) -> LocalizedStringKey {
        switch problem {
        case .permissionUndecided:
            "The app needs your location to find the nearest station. Allow location below, then try again."
        case .permissionDenied:
            "The app cannot find the nearest station without your location. Turn on Location in Settings."
        case .noStationNearby:
            "No metro or RER station was found within \(walkingDistance) of you."
        case .locationUnavailable:
            "Your position is not available right now. Try again in a moment."
        }
    }
}
