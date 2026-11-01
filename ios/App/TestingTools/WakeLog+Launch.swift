#if WAKE_LOG
import TROMECore
import UIKit

extension WakeLog {
    /// The lines of a launch. The second comes one turn later, once iOS says whether it started the app in the
    /// background (for an event of a watched area) or on screen.
    func recordLaunch(locationSource: LocationSource) {
        let phone = PhoneStateReport.launchLines(locationSource: locationSource)
        record(.launch, (["App launched"] + phone).joined(separator: "\n"))
        Task { @MainActor in
            let started = UIApplication.shared.applicationState == .background
                ? "Started by iOS, in the background"
                : "Started on screen"
            let later = await PhoneStateReport.laterLines()
            record(.launch, (["Phone at launch", started] + later).joined(separator: "\n"))
        }
    }
}
#endif
