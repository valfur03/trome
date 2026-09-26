import RATPCore
import SwiftUI

struct ContentView: View {
    @Environment(LocationService.self) private var locationService
    private let primConfiguration = PRIMConfiguration(infoDictionary: Bundle.main.infoDictionary)

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("RATP Activity")
                    .font(.largeTitle.bold())
                    .accessibilityIdentifier("appTitle")
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
                .padding(.top, 24)
                #endif
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
        .environment(LocationService.makeForThisBuild())
}
