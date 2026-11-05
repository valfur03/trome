#if WAKE_LOG
import TROMECore
import UIKit

extension WakeLog {
    /// The lines of a launch. The second comes one turn later, with the settings that iOS gives only then. How the
    /// launch began comes once a screen of the app is in front, or at the end of `openWindow` with none.
    /// iOS can run the app's init ahead of a launch (a prewarm) and pause it before `UIApplicationMain`: it then sets
    /// `ActivePrewarm`, and the first turn of the main thread is the launch.
    func recordLaunch(locationSource: LocationSource) {
        recordLaunch(
            AppBuild(infoDictionary: Bundle.main.infoDictionary),
            iOSVersion: UIDevice.current.systemVersion,
            phone: PhoneStateReport.launchLines(locationSource: locationSource),
            preparedInAdvance: ProcessInfo.processInfo.environment["ActivePrewarm"] == "1"
        )
        Task { @MainActor in
            let later = await PhoneStateReport.laterLines()
            record(.launch, (["Phone at launch"] + later).joined(separator: "\n"))
        }
        Task { @MainActor in
            recordLaunchResumed()
            try? await Task.sleep(for: Self.openWindow)
            recordOpenWindowEnd()
        }
    }
}
#endif
