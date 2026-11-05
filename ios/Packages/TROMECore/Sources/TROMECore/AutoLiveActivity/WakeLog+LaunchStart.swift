import Foundation

extension WakeLog {
    /// Set while a launch has not told how it began, across launches: the next launch then tells it as unknown.
    static let launchStartPendingKey = "testingTools.wakeLog.launchStartPending"
    static let resumedLine = "Launch resumed: iOS had prepared the app in advance"

    /// The first line of a launch: the build, its commit and the iOS version, then `phone`, the settings of the phone.
    /// Before it comes the line of the previous launch when that one never told how it began.
    /// `preparedInAdvance`: iOS ran this launch ahead of time (a prewarm), up to the app's init, and paused it; the
    /// launch then counts from `recordLaunchResumed`, so that a tap hours later never reads as a run of iOS.
    public func recordLaunch(_ build: AppBuild, iOSVersion: String, phone: [String], preparedInAdvance: Bool = false) {
        if storage.data(forKey: Self.launchStartPendingKey) != nil {
            record(.launch, LaunchStart.unknownLine)
        }
        let summary = build.summary(iOSVersion: iOSVersion) + (preparedInAdvance ? ", prepared in advance by iOS" : "")
        if preparedInAdvance {
            // iOS may also drop a launch that it prepared and never resumed: that one has nothing to tell.
            storage.set(nil, forKey: Self.launchStartPendingKey)
            waitsForResume = true
        } else {
            storage.set(Data([1]), forKey: Self.launchStartPendingKey)
        }
        record(.launch, (["App launched: \(summary)"] + phone).joined(separator: "\n"))
    }

    /// The app calls it at its first turn on the main thread, which a launch that iOS prepared in advance reaches only
    /// once iOS resumes it. Nothing for any other launch.
    public func recordLaunchResumed() {
        guard waitsForResume else { return }
        waitsForResume = false
        launchedAt = now()
        storage.set(Data([1]), forKey: Self.launchStartPendingKey)
        record(.launch, Self.resumedLine)
    }

    /// The app calls it `openWindow` after the launch.
    public func recordOpenWindowEnd() {
        guard !waitsForResume else { return }
        write(launchStart.openWindowEnded())
    }

    public static var openWindow: Duration { .seconds(LaunchStart.openWindow) }

    func recordScreenOnFront() {
        // A screen can come before the first turn of the main thread runs: the launch was resumed by then.
        recordLaunchResumed()
        record(.launch, "App on screen")
        write(launchStart.screenCameToFront(after: now().timeIntervalSince(launchedAt)))
    }

    private func write(_ lines: [String]) {
        for line in lines {
            record(.launch, line)
        }
        if !launchStart.isPending {
            storage.set(nil, forKey: Self.launchStartPendingKey)
        }
    }
}
