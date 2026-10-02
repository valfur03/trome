import RATPCore
import SwiftUI

struct ContentView: View {
    let nearestStationModel: NearestStationModel
    let permissions: PermissionsModel
    let primConfiguration: PRIMConfiguration?

    @Environment(LocationService.self) private var locationService
    @Environment(AutoLiveActivityModel.self) private var autoLiveActivity
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appName) private var appName

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: appName)
                        .font(.largeTitle.bold())
                        .accessibilityIdentifier("appTitle")
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                NearestStationLiveActivitySection(nearestStationModel: nearestStationModel)
                AutomaticModeSection()
                PermissionsSection(permissions: permissions, nearestStationModel: nearestStationModel)
                #if DEBUG
                if case .fake(let fakePosition) = locationService.source {
                    Label("Fake position: \(fakePosition.name)", systemImage: "location.slash.fill")
                        .font(.footnote.bold())
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("fakePositionBanner")
                        .listRowBackground(Color.clear)
                }
                #endif
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        TrainDataSourceNotice()
                        StationDataSourceNotice()
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                }
            }
            #if DEBUG
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Testing tools") {
                        TestingToolsView(nearestStationModel: nearestStationModel, primConfiguration: primConfiguration)
                    }
                    .accessibilityIdentifier("testingTools")
                }
            }
            #endif
        }
        .onChange(of: scenePhase, initial: true) {
            autoLiveActivity.setAppPhase(AppPhase(scenePhase))
            guard scenePhase == .active else { return }
            Task { await permissions.refresh() }
            Task {
                await nearestStationModel.refresh()
                await autoLiveActivity.appDidBecomeActive()
            }
        }
        .onChange(of: autoLiveActivity.hasAskedNotificationQuestion) {
            Task { await permissions.refresh() }
        }
    }
}

private extension AppPhase {
    init(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active: self = .active
        case .inactive: self = .inactive
        default: self = .background
        }
    }
}
