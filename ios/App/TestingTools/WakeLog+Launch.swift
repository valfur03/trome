#if DEBUG
import TROMECore

extension WakeLog {
    func recordLaunch(locationSource: LocationSource) {
        Task { @MainActor in
            let phone = await PhoneStateReport.lines(locationSource: locationSource)
            record(.launch, (["App launched"] + phone).joined(separator: "\n"))
        }
    }
}
#endif
