import Foundation

/// Gets the next trains of a station from the PRIM "stop-monitoring" API, or from the server of the app,
/// which gives the PRIM answer as PRIM gave it (`TrainDataSource`).
///
/// It asks once for each stop area of the given stations, which are the station and the other stations
/// of its place (`StationCatalog.hubStations(of:)`): 2 calls for Châtelet, 5 for Saint-Lazare.
/// A metro line with no stop area asks for each of its quays (`PRIMStopReference`).
/// The answer for a stop area can hold trains of lines that the app gives to another station of the place,
/// so it keeps only the trains of the lines that it asked this stop area for.
/// It throws the error of a failed call only when no train is left from the other calls;
/// else it says which stops did not answer (`DeparturesAnswer.unansweredStops`).
public struct PRIMDeparturesProvider: DeparturesProvider {
    public static let endpoint = URL(string: "https://prim.iledefrance-mobilites.fr/marketplace/stop-monitoring")!
    static let timeout: TimeInterval = 15

    private let source: TrainDataSource
    private let httpClient: any HTTPClient
    private let log: (@Sendable (String) -> Void)?
    private let now: @Sendable () -> Date
    private let retrySchedule = ServerRetrySchedule()

    public init(
        source: TrainDataSource,
        httpClient: any HTTPClient = URLSession.shared,
        log: (@Sendable (String) -> Void)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source
        self.httpClient = httpClient
        self.log = log
        self.now = now
    }

    public init(
        apiKey: String,
        httpClient: any HTTPClient = URLSession.shared,
        log: (@Sendable (String) -> Void)? = nil
    ) {
        self.init(source: .prim(apiKey: apiKey), httpClient: httpClient, log: log)
    }

    struct StopRequest: Equatable {
        let monitoringRef: String
        var lineCodes: Set<String>
    }

    struct Answer {
        let stopRequest: StopRequest
        let visits: Result<[MonitoredVisit], any Error>
        var answeredAt: Date?

        var failed: Bool {
            if case .failure = visits { true } else { false }
        }
    }

    struct StopAnswer {
        let visits: [MonitoredVisit]
        let answeredAt: Date?
    }

    enum VisitOutcome: Equatable {
        case kept(Departure)
        case dropped(String)
    }

    public func departures(at stations: [Station]) async throws -> [Departure] {
        try await departuresAnswer(at: stations).departures
    }

    public func departuresAnswer(at stations: [Station]) async throws -> DeparturesAnswer {
        let stopRequests = Self.stopRequests(for: stations)
        let answers = await withTaskGroup(of: Answer.self) { group in
            for stopRequest in stopRequests {
                group.addTask {
                    do {
                        let stopAnswer = try await stopAnswer(at: stopRequest.monitoringRef)
                        return Answer(
                            stopRequest: stopRequest,
                            visits: .success(stopAnswer.visits),
                            answeredAt: stopAnswer.answeredAt
                        )
                    } catch {
                        return Answer(stopRequest: stopRequest, visits: .failure(error))
                    }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        try Task.checkCancellation()

        let visits = answers.flatMap { answer in
            ((try? answer.visits.get()) ?? []).compactMap { Self.visit($0, askedBy: answer.stopRequest) }
        }
        let departures = Self.departures(from: visits, at: stations)
        if let log {
            PRIMAnswerLog.lines(of: answers, at: stations, now: Date()).forEach(log)
        }
        if departures.isEmpty, let error = Self.error(of: answers) {
            throw error
        }
        return DeparturesAnswer(
            departures: departures,
            answeredAt: answers.compactMap(\.answeredAt).min(),
            unansweredStops: Set(answers.filter(\.failed).map(\.stopRequest.monitoringRef))
        )
    }

    static func error(of answers: [Answer]) -> (any Error)? {
        let errors = answers.compactMap { answer -> (any Error)? in
            if case .failure(let error) = answer.visits { error } else { nil }
        }
        let latestRetry = errors.compactMap { ($0 as? NextTrainsError)?.serverRetryAt }.max()
        return latestRetry.map { NextTrainsError.serverOut(retryAt: $0) } ?? errors.first
    }

    static func stopRequests(for stations: [Station]) -> [StopRequest] {
        var stopRequests: [StopRequest] = []
        for line in stations.flatMap(\.lines) {
            guard let lineCode = line.primLineCode else { continue }
            for monitoringRef in PRIMStopReference.monitoringRefs(of: line) {
                if let index = stopRequests.firstIndex(where: { $0.monitoringRef == monitoringRef }) {
                    stopRequests[index].lineCodes.insert(lineCode)
                } else {
                    stopRequests.append(StopRequest(monitoringRef: monitoringRef, lineCodes: [lineCode]))
                }
            }
        }
        return stopRequests
    }

    static func visit(_ visit: MonitoredVisit, askedBy stopRequest: StopRequest) -> MonitoredVisit? {
        guard let lineCode = PRIMStopReference.lineCode(fromLineRef: visit.lineRef),
              stopRequest.lineCodes.contains(lineCode)
        else {
            return nil
        }
        var visit = visit
        if PRIMStopReference.isQuay(stopRequest.monitoringRef) {
            visit.quayRef = stopRequest.monitoringRef
        } else if visit.quayRef == nil,
                  let monitoringRef = visit.monitoringRef,
                  PRIMStopReference.isQuay(monitoringRef) {
            visit.quayRef = monitoringRef
        }
        return visit
    }

    static func departures(from visits: [MonitoredVisit], at stations: [Station]) -> [Departure] {
        outcomes(of: visits, at: stations).compactMap { outcome in
            if case .kept(let departure) = outcome { departure } else { nil }
        }
    }

    static func outcomes(of visits: [MonitoredVisit], at stations: [Station]) -> [VisitOutcome] {
        let linesByCode = Dictionary(
            stations.flatMap { station in
                station.lines.compactMap { line in
                    line.primLineCode.map { ($0, (line: line, stationKey: StationCatalog.searchKey(station.name))) }
                }
            },
            uniquingKeysWith: { first, _ in first }
        )
        var seenJourneys: Set<String> = []
        return visits.map { visit in
            guard !visit.isCancelled else { return .dropped("cancelled") }
            guard let (line, stationKey) = PRIMStopReference.lineCode(fromLineRef: visit.lineRef)
                    .flatMap({ linesByCode[$0] })
            else {
                return .dropped("other line")
            }
            guard visit.destinationRef == nil || visit.destinationRef != visit.monitoringRef,
                  StationCatalog.searchKey(visit.destinationName) != stationKey
            else {
                return .dropped("ends here")
            }
            let journeyKey = visit.journeyRef.map { "\(line.mode)-\(line.name)-\($0)" }
                ?? "\(line.mode)-\(line.name)-\(visit.destinationName)-\(visit.time.timeIntervalSince1970)"
            guard seenJourneys.insert(journeyKey).inserted else {
                return .dropped("same journey as an earlier visit")
            }
            return .kept(Departure(
                line: line,
                destination: visit.destinationName,
                time: visit.time,
                quayRef: visit.quayRef,
                directionRef: visit.directionRef,
                arrivalTime: visit.arrivalTime,
                isAtStop: visit.isAtStop
            ))
        }
    }

    func request(for monitoringRef: String) -> URLRequest {
        var request: URLRequest
        switch source {
        case .prim(let apiKey):
            var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "MonitoringRef", value: monitoringRef)]
            request = URLRequest(url: components.url!, timeoutInterval: Self.timeout)
            request.setValue(apiKey, forHTTPHeaderField: "apikey")
        case .server(let server):
            request = URLRequest(url: Self.serverURL(of: server, for: monitoringRef), timeoutInterval: Self.timeout)
            request.setValue("Bearer \(server.appToken)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func serverURL(of server: TrainServerConfiguration, for monitoringRef: String) -> URL {
        server.baseURL
            .appending(path: "v1")
            .appending(path: "stops")
            .appending(path: monitoringRef)
            .appending(path: "departures")
    }

    /// One call for one stop, as the server of the app sees it: the request, the wait for a retry time, and the
    /// reading of the answer. `BuildPromisesTests` judges it against the newest recorded set of promises.
    func stopAnswer(at monitoringRef: String) async throws -> StopAnswer {
        try waitForTheRetryTime(of: monitoringRef)
        let (data, httpResponse) = try await answer(at: monitoringRef)
        try keepTheRetryTime(of: monitoringRef, from: httpResponse, body: data)
        try AppTokenRefusal.throwIfRefused(httpResponse, body: data, from: source)
        if let error = Self.error(ofStatus: httpResponse?.statusCode, from: source) {
            throw error
        }
        let answeredAt: Date?
        switch source {
        case .prim:
            answeredAt = nil
        case .server:
            guard let lastModified = httpResponse.flatMap(HTTPDate.lastModified) else {
                throw NextTrainsError.serviceFailure
            }
            answeredAt = lastModified
        }

        do {
            return StopAnswer(visits: try StopMonitoringResponse.visits(from: data), answeredAt: answeredAt)
        } catch {
            throw NextTrainsError.serviceFailure
        }
    }

    private func answer(at monitoringRef: String) async throws -> (Data, HTTPURLResponse?) {
        do {
            let (data, response) = try await httpClient.data(for: request(for: monitoringRef))
            return (data, response as? HTTPURLResponse)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw NextTrainsError.unreachable
        }
    }

    private func waitForTheRetryTime(of monitoringRef: String) throws {
        guard case .server = source, let error = retrySchedule.error(waitingFor: monitoringRef, now: now()) else {
            return
        }
        throw error
    }

    private func keepTheRetryTime(of monitoringRef: String, from response: HTTPURLResponse?, body: Data) throws {
        guard case .server = source else { return }
        guard let out = ServerOutAnswer(response: response, body: body, now: now()) else {
            retrySchedule.forget(monitoringRef)
            return
        }
        retrySchedule.wait(for: out, at: monitoringRef)
        throw out.error
    }

    static func error(ofStatus statusCode: Int?, from source: TrainDataSource) -> NextTrainsError? {
        switch (statusCode, source) {
        case (.some(200..<300), _):
            nil
        case (.some(401), .prim), (.some(403), .prim):
            .keyRejected
        case (.some(429), .prim):
            .quotaExceeded
        default:
            .serviceFailure
        }
    }
}
