import RATPCore
import SwiftUI

struct ContentView: View {
    let nearestStationModel: NearestStationModel

    @Environment(LocationService.self) private var locationService
    @Environment(\.scenePhase) private var scenePhase
    private let primConfiguration = PRIMConfiguration(infoDictionary: Bundle.main.infoDictionary)

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("RATP Activity")
                    .font(.largeTitle.bold())
                    .accessibilityIdentifier("appTitle")
                NearestStationView(state: nearestStationModel.state)
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
                NavigationLink("Testing tools") {
                    TestingToolsView()
                }
                .accessibilityIdentifier("testingTools")
                #endif
            }
            .padding()
        }
        .onChange(of: scenePhase, initial: true) {
            guard scenePhase == .active else { return }
            Task { await nearestStationModel.refresh() }
        }
    }
}
