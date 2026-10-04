#if os(iOS)
import AppIntents

public struct SnoozeLiveActivityIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Snooze the Live Activity"
    public static let isDiscoverable = false

    @Parameter(title: "Duration")
    public var duration: SnoozeDuration

    @Dependency private var autoLiveActivity: AutoLiveActivityModel

    public init() {}

    public init(duration: SnoozeDuration) {
        self.duration = duration
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        await autoLiveActivity.snoozeTappedOnTheLockScreen(for: duration)
        return .result()
    }
}

extension SnoozeDuration: AppEnum {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Snooze duration"
    public static let caseDisplayRepresentations: [SnoozeDuration: DisplayRepresentation] = [
        .thirtyMinutes: "30 minutes",
        .oneHour: "1 hour",
        .restOfToday: "For the rest of today"
    ]
}

public struct TROMECoreAppIntents: AppIntentsPackage {}
#endif
