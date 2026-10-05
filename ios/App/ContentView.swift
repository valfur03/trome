import TROMECore
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
            ScrollView {
                VStack(alignment: .leading, spacing: NightLook.cardSpacing) {
                    Text(verbatim: appName)
                        .font(.largeTitle.bold())
                        .foregroundStyle(NightLook.text)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("appTitle")
                        .padding(.horizontal, 4)
                    ServerOutSection()
                    LiveActivityStateSection()
                    ExampleRow()
                    AutomaticModeSection()
                    PermissionsSection(permissions: permissions, nearestStationModel: nearestStationModel)
                    #if DEBUG
                    if case .fake(let fakePosition) = locationService.source {
                        Label("Fake position: \(fakePosition.name)", systemImage: "location.slash.fill")
                            .font(.footnote.bold())
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("fakePositionBanner")
                            .padding(.horizontal, 4)
                    }
                    #endif
                    AboutSection()
                    VStack(alignment: .leading, spacing: 8) {
                        TrainDataSourceNotice()
                        StationDataSourceNotice()
                    }
                    .font(.footnote)
                    .foregroundStyle(NightLook.secondaryText)
                    .tint(NightLook.link)
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, NightLook.pageMargin)
                .padding(.bottom, NightLook.pageMargin)
            }
            .background(NightLook.page.ignoresSafeArea())
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
