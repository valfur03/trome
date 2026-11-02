#if DEBUG
import os
import TROMECore

extension PRIMDeparturesProvider {
    nonisolated private static let answerLogger = Logger(category: "PRIM")

    static func loggingEachAnswer(apiKey: String, walkRecord: WakeLog?) -> PRIMDeparturesProvider {
        PRIMDeparturesProvider(
            source: .prim(apiKey: apiKey),
            log: { line in answerLogger.notice("\(line, privacy: .public)") },
            walkRecord: walkRecord
        )
    }
}
#endif
