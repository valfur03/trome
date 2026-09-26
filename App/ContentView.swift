import RATPCore
import SwiftUI
import UIKit

struct ContentView: View {
    let nearestStationModel: NearestStationModel
    let locationPermission: CoreLocationPermission
    let primConfiguration: PRIMConfiguration?

    @Environment(LocationService.self) private var locationService
    @Environment(AutoLiveActivityModel.self) private var autoLiveActivity
    @Environment(\.scenePhase) private var scenePhase
    @State private var allowsBackgroundDetection = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("RATP Activity")
                        .font(.largeTitle.bold())
                        .accessibilityIdentifier("appTitle")
                    NearestStationView(state: nearestStationModel.state)
                    if !allowsBackgroundDetection, case .found = nearestStationModel.state {
                        BackgroundDetectionHint()
                    }
                    Divider()
                    NextTrainsSection()
                    Text(primConfiguration == nil ? "Train data key: not set" : "Train data key: set")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("primKeyStatus")
                    #if DEBUG
                    if case .fake(let fakePosition) = locationService.source {
                        Label("Fake position: \(fakePosition.name)", systemImage: "location.slash.fill")
                            .font(.footnote.bold())
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("fakePositionBanner")
                    }
                    #endif
                }
                .padding()
            }
            #if DEBUG
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Testing tools") {
                        TestingToolsView()
                    }
                    .accessibilityIdentifier("testingTools")
                }
            }
            #endif
        }
        .onChange(of: scenePhase, initial: true) {
            guard scenePhase == .active else {
                Task { await autoLiveActivity.setAppActive(false) }
                return
            }
            Task {
                await nearestStationModel.refresh()
                allowsBackgroundDetection = locationPermission.allowsBackgroundDetection
                await autoLiveActivity.setAppActive(scenePhase == .active)
            }
        }
    }
}

private struct BackgroundDetectionHint: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 8) {
            Text(
                "The app can show the next trains by itself near a station only while it is open. "
                    + "To get a notification when it is closed, set Location to Always in Settings."
            )
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("backgroundDetectionHint")
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            }
            .font(.footnote)
            .accessibilityIdentifier("backgroundDetectionSettingsButton")
        }
    }
}
