#if WAKE_LOG
import TROMECore
import UIKit

extension WakeLog {
    /// The lines of a launch. The second comes one turn later, with the settings that iOS gives only then. How the
    /// launch began comes once a screen of the app is in front, or at the end of `openWindow` with none.
    func recordLaunch(locationSource: LocationSource) {
        recordLaunch(
            AppBuild(infoDictionary: Bundle.main.infoDictionary),
            iOSVersion: UIDevice.current.systemVersion,
            phone: PhoneStateReport.launchLines(locationSource: locationSource)
        )
        Task { @MainActor in
            let later = await PhoneStateReport.laterLines()
            record(.launch, (["Phone at launch"] + later).joined(separator: "\n"))
        }
        Task { @MainActor in
            try? await Task.sleep(for: Self.openWindow)
            recordOpenWindowEnd()
        }
    }
}
#endif
