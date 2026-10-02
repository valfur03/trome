#if DEBUG
import os
import RATPCore

extension PRIMDeparturesProvider {
    nonisolated private static let answerLogger = Logger(subsystem: "RATPActivity", category: "PRIM")

    static func loggingEachAnswer(apiKey: String) -> PRIMDeparturesProvider {
        PRIMDeparturesProvider(apiKey: apiKey) { line in
            answerLogger.notice("\(line, privacy: .public)")
        }
    }
}
#endif
