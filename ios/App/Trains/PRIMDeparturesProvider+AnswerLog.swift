#if DEBUG
import os
import TROMECore

extension PRIMDeparturesProvider {
    nonisolated private static let answerLogger = Logger(category: "PRIM")

    static func loggingEachAnswer(apiKey: String) -> PRIMDeparturesProvider {
        PRIMDeparturesProvider(apiKey: apiKey) { line in
            answerLogger.notice("\(line, privacy: .public)")
        }
    }
}
#endif
