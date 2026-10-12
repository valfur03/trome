import Foundation
@testable import TROMECore

/// A reply of the server that keeps a promise, and what it means for the build.
struct PromisedReply {
    /// The time of the request: 2026-10-02T08:30:00Z, a time of the day of the recorded PRIM answers.
    static let now = Date(timeIntervalSince1970: 1_790_929_800)

    var status = 200
    var headers: [String: String] = [:]
    var json: [String: Any]?
    var primAnswer: Data?
    /// The time that Last-Modified says: the build shows it as the time of the answer.
    var answeredAt: Date?
    /// The retry time that the reply gives, before the shortest wait of the build.
    var retryAt: Date?
    var shown: [String] = []

    var stubReply: ServerStubHTTPClient.Reply {
        let json = json.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: .sortedKeys) }
        return .init(body: primAnswer ?? json ?? Data(), status: status, headers: headers)
    }
}

/// One way to keep one part of a promise: a status, a header, a body key.
struct ReplySample {
    let shown: String
    let apply: (inout PromisedReply) -> Void
}

/// A value that the server may give, and the time that it says, if any.
struct SampleValue {
    let value: Matcher.Value
    var date: Date?

    var text: String {
        switch value {
        case .text(let text): text
        case .number(let number): String(number)
        }
    }
}

extension PromisedAnswer {
    /// Replies that keep this promise for the stop: each value that this test knows for each part of the reply,
    /// with the other parts at their first value (each value once, not every combination).
    /// A value comes from the matcher (`is`, `oneOf`), else from the samples of its name below, and must keep
    /// every matcher of its part; a part with no such value fails, so that a new form is taught here.
    func replies(at stop: BuildPromiseSet.Stop, of set: BuildPromiseSet) throws -> [PromisedReply] {
        var first = PromisedReply()
        if body.primAnswer == true {
            first.primAnswer = try set.data(of: prim ?? stop.prim)
        }
        if body.json != nil {
            first.json = [:]
        }
        let parts = try [statusSamples()] + headerSamples() + retryTimeSamples() + jsonSamples()
        let firstChoice = parts.map { $0[0] }
        var choices = [firstChoice]
        for (index, samples) in parts.enumerated() {
            for sample in samples.dropFirst() {
                var choice = firstChoice
                choice[index] = sample
                choices.append(choice)
            }
        }
        return choices.map { choice in
            choice.reduce(into: first) { reply, sample in
                sample.apply(&reply)
                reply.shown.append(sample.shown)
            }
        }
    }

    private func statusSamples() throws -> [ReplySample] {
        // The 1xx statuses are left out: the system never gives them to the app as an answer.
        let statuses = (200..<600).filter { code in
            (status.exact.map { $0 == code } ?? true)
                && (status.class.map { Self.status(code, isIn: $0) } ?? true)
                && (status.notClass.map { !Self.status(code, isIn: $0) } ?? true)
        }
        guard !statuses.isEmpty else { throw BuildPromiseSetError.unknown("a status of \"\(when)\"") }
        return statuses.map { code in ReplySample(shown: "status \(code)") { $0.status = code } }
    }

    private static func status(_ code: Int, isIn statusClass: String) -> Bool {
        statusClass.count == 3 && statusClass.hasSuffix("xx") && statusClass.first == String(code / 100).first
    }

    private func headerSamples() throws -> [[ReplySample]] {
        try (headers ?? [:]).sorted { $0.key < $1.key }.map { name, matcher in
            try Self.values(of: matcher, named: name).map { value in
                ReplySample(shown: "\(name): \(value?.text ?? "absent")") { reply in
                    reply.headers[name] = value?.text
                    if name == "last-modified" {
                        reply.answeredAt = value?.date
                    }
                }
            }
        }
    }

    private func retryTimeSamples() throws -> [[ReplySample]] {
        guard let retryTime else { return [] }
        let bodyMatcher = body.json?[retryTime.orBodyKey]
        let headerAlone = bodyMatcher?.optional ?? true
        let inHeader = (Self.samples[retryTime.header] ?? []).filter { sample in
            headerAlone && Matcher.text(sample.text, isIn: retryTime.headerForm)
        }
        let inBody = (Self.samples[retryTime.orBodyKey] ?? []).filter { sample in
            Matcher.text(sample.text, isIn: retryTime.bodyKeyForm) && (bodyMatcher?.allows(sample.value) ?? true)
        }
        guard !inBody.isEmpty, !inHeader.isEmpty || !headerAlone else {
            throw BuildPromiseSetError.unknown("a retry time in the forms of \"\(when)\"")
        }
        let samples = inHeader.map { sample in
            ReplySample(shown: "\(retryTime.header): \(sample.text.debugDescription)") { reply in
                reply.headers[retryTime.header] = sample.text
                reply.retryAt = sample.date
            }
        } + inBody.map { sample in
            ReplySample(shown: "\(retryTime.orBodyKey): \(sample.text)") { reply in
                reply.json?[retryTime.orBodyKey] = sample.text
                reply.retryAt = sample.date
            }
        }
        return [samples]
    }

    private func jsonSamples() throws -> [[ReplySample]] {
        guard let json = body.json else { return [] }
        let keys = try json.sorted { $0.key < $1.key }.filter { $0.key != retryTime?.orBodyKey }.map { key, matcher in
            try Self.values(of: matcher, named: key).map { value in
                ReplySample(shown: "\(key): \(value?.text ?? "absent")") { $0.json?[key] = value?.value.json }
            }
        }
        // The server may add a key next to the promised ones: the server check judges only the promised keys.
        let otherKey = "otherKey"
        let other = json[otherKey] == nil ? [[
            ReplySample(shown: "no other key") { _ in },
            ReplySample(shown: "an other key") { $0.json?[otherKey] = "a key that a later server may add" }
        ]] : []
        return keys + other
    }

    private static func values(of matcher: Matcher, named name: String) throws -> [SampleValue?] {
        let candidates = matcher.exact.map { [SampleValue(value: $0)] }
            ?? matcher.oneOf.map { $0.map { SampleValue(value: .text($0)) } }
            ?? samples[name]
            ?? (matcher.type == "string" ? [SampleValue(value: .text("any text"))] : [])
        let allowed = candidates.filter { matcher.allows($0.value) }
        guard !allowed.isEmpty else { throw BuildPromiseSetError.unknown("a value of \(name) that the set allows") }
        return allowed + (matcher.optional == true ? [nil] : [])
    }

    /// The values that this test knows, by name of header or body key.
    static let samples: [String: [SampleValue]] = [
        "last-modified": lastModifiedSamples,
        "cache-control": ["no-store", "no-store, max-age=0", "private, no-store", "no-cache, no-store, must-revalidate"]
            .map { SampleValue(value: .text($0)) },
        "retry-after": [("120", 120), ("1", 1), (" 45 ", 45), ("\t90.5\t", 90.5), ("0", 0)].map { text, seconds in
            SampleValue(value: .text(text), date: PromisedReply.now.addingTimeInterval(seconds))
        },
        "retryAt": [
            ("2026-10-02T09:00:00Z", 1_800), ("2026-10-02T09:00:00.250Z", 1_800.25),
            ("2026-10-02T11:00:00+02:00", 1_800), ("2026-10-02T08:30:05Z", 5)
        ].map { text, seconds in
            SampleValue(value: .text(text), date: PromisedReply.now.addingTimeInterval(seconds))
        },
        // A reason that no build knows, and every reason that this app reads as the server out.
        "reason": (["prim-failure", "a-reason-that-no-build-knows"] + ServerOutAnswer.reasonsOfAnEmptyBudget.sorted())
            .map { SampleValue(value: .text($0)) }
    ]

    /// Dates of every day of the week and every month, written as an HTTP date (RFC 9110, IMF-fixdate).
    private static var lastModifiedSamples: [SampleValue] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return (0..<14).map { index in
            let date = PromisedReply.now.addingTimeInterval(-Double(index) * (32 * 86_400 + 3_661))
            return SampleValue(value: .text(formatter.string(from: date)), date: date)
        }
    }
}
