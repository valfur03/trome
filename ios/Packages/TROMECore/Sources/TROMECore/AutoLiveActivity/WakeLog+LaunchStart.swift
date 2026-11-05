import Foundation

extension WakeLog {
    /// Set while a launch has not told how it began, across launches: the next launch then tells it as unknown.
    static let launchStartPendingKey = "testingTools.wakeLog.launchStartPending"

    /// The first line of a launch: the build, its commit and the iOS version, then `phone`, the settings of the phone.
    /// Before it comes the line of the previous launch when that one never told how it began.
    public func recordLaunch(_ build: AppBuild, iOSVersion: String, phone: [String]) {
        if storage.data(forKey: Self.launchStartPendingKey) != nil {
            record(.launch, LaunchStart.unknownLine)
        }
        storage.set(Data([1]), forKey: Self.launchStartPendingKey)
        record(.launch, (["App launched: \(build.summary(iOSVersion: iOSVersion))"] + phone).joined(separator: "\n"))
    }

    /// The app calls it `openWindow` after the launch.
    public func recordOpenWindowEnd() {
        write(launchStart.openWindowEnded())
    }

    public static var openWindow: Duration { .seconds(LaunchStart.openWindow) }

    func recordScreenOnFront() {
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
