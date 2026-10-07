#if DEBUG
import TROMECore

extension WakeLog {
    func recordLaunch(locationSource: LocationSource) {
        let phone = PhoneStateReport.launchLines(locationSource: locationSource)
        record(.launch, (["App launched"] + phone).joined(separator: "\n"))
        Task { @MainActor in
            record(.launch, (["Phone at launch"] + (await PhoneStateReport.laterLines())).joined(separator: "\n"))
        }
    }
}
#endif
