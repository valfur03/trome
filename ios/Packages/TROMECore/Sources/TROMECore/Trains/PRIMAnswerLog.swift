import Foundation

enum PRIMAnswerLog {
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
            let prefix = "PRIM \(answer.stopRequest.monitoringRef)"
            switch answer.visits {
            case .failure(let error):
                return ["\(prefix) | failed: \(error)"]
            case .success(let visits):
                let visitLines = zip(visits, indices).map { visit, index in
                    let shown = index.map { asked[$0] } ?? visit
                    let fate = index.map { describe(outcomes[$0], of: shown, now: now) } ?? "dropped, line not asked"
                    return "\(prefix) | \(fate) | \(describe(shown, timeStyle: timeStyle))"
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
