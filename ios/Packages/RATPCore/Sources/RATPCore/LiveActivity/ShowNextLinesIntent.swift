#if os(iOS)
import AppIntents

public struct ShowNextLinesIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Show the next lines of the station"
    public static let isDiscoverable = false

    @Dependency private var liveActivity: StationLiveActivityModel

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        await liveActivity.showNextLines()
        return .result()
    }
}
#endif
