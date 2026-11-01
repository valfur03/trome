import Foundation

/// The lines of the debug log for the PRIM answers of one refresh: for each call, one line with its number of
/// entries (or its error), then one group of lines for each entry, which say what the app does with it.
/// Each line starts with the stop and the time of the call (`call`, by the app's clock, in UTC), and each entry
/// line with its rank in the answer (`entry`), so that a script can put the lines of one entry together.
/// A Debug build adds a `fields` line to each entry: the fields of `PRIMLogFields`, as PRIM gave them, each
/// as its PRIM name and its value, and `absent` when the answer does not have it.
/// The fields go on a line of their own because the log of the phone cuts a line after 1024 bytes.
enum PRIMAnswerLog {
    private static let callTimeStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func lines(
        of answers: [PRIMDeparturesProvider.Answer],
        at stations: [Station],
        now: Date,
        timeZone: TimeZone = .current
    ) -> [String] {
        var asked: [MonitoredVisit] = []
        let askedIndices = answers.map { answer in
            ((try? answer.visits.get()) ?? []).map { visit -> Int? in
                guard let visit = PRIMDeparturesProvider.visit(visit, askedBy: answer.stopRequest) else { return nil }
                asked.append(visit)
                return asked.count - 1
            }
        }
        let outcomes = PRIMDeparturesProvider.outcomes(of: asked, at: stations)
        let timeStyle = Date.ISO8601FormatStyle(timeZone: timeZone).time(includingFractionalSeconds: false)
        return zip(answers, askedIndices).flatMap { answer, indices -> [String] in
            let callTime = answer.askedAt?.formatted(callTimeStyle) ?? "absent"
            let prefix = "PRIM \(answer.stopRequest.monitoringRef) | call \(callTime)"
            switch answer.visits {
            case .failure(let error):
                return ["\(prefix) | failed: \(error)"]
            case .success(let visits):
                let visitLines = zip(visits, indices).enumerated().flatMap { rank, pair in
                    let (visit, index) = pair
                    let shown = index.map { asked[$0] } ?? visit
                    let fate = index.map { describe(outcomes[$0], of: shown, now: now) } ?? "dropped, line not asked"
                    let entryPrefix = "\(prefix) | entry \(rank + 1)"
                    return ["\(entryPrefix) | \(fate) | \(describe(shown, timeStyle: timeStyle))"]
                        + fieldLines(of: visit, prefix: entryPrefix)
                }
                return ["\(prefix) | \(visits.count) visits"] + visitLines
            }
        }
    }

    private static func describe(
        _ outcome: PRIMDeparturesProvider.VisitOutcome,
        of visit: MonitoredVisit,
        now: Date
    ) -> String {
        switch outcome {
        case .dropped(let reason):
            "dropped, \(reason)"
        case .kept where DepartureBoard.hasLeft(at: visit.time, now: now):
            "dropped, left at least \(Int(DepartureBoard.departedGraceSeconds)) s ago"
        case .kept where visit.time <= now:
            "kept, time passed (not on the Live Activity)"
        case .kept where DepartureBoard.isOverAnHourAway(visit.time, now: now):
            "kept, over 1 h away"
        case .kept:
            "kept"
        }
    }

    private static func fieldLines(of visit: MonitoredVisit, prefix: String) -> [String] {
        #if DEBUG
        guard !visit.logFields.fields.isEmpty else { return [] }
        let fields = visit.logFields.fields.map { name, value in "\(name) \(value?.text ?? "absent")" }
        return [(["\(prefix) | fields"] + fields).joined(separator: " | ")]
        #else
        []
        #endif
    }

    private static func describe(_ visit: MonitoredVisit, timeStyle: Date.ISO8601FormatStyle) -> String {
        let fields: [(String, String?)] = [
            ("line", visit.lineRef),
            ("to", visit.destinationName),
            ("time", visit.time.formatted(timeStyle)),
            ("arrival", visit.arrivalTime?.formatted(timeStyle)),
            ("aimed", visit.aimedTime?.formatted(timeStyle)),
            ("status", visit.status),
            ("at stop", visit.isAtStop ? "yes" : nil),
            ("quay", visit.quayRef),
            ("direction", visit.directionRef),
            ("destination", visit.destinationRef),
            ("journey", visit.journeyRef),
            ("item", visit.itemIdentifier)
        ]
        return fields.compactMap { name, value in value.map { "\(name) \($0)" } }.joined(separator: " | ")
    }
}
