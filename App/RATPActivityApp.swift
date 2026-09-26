import RATPCore
import SwiftUI

@main
struct RATPActivityApp: App {
    @State private var locationService = LocationService.makeForThisBuild()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(locationService)
        }
    }
}
