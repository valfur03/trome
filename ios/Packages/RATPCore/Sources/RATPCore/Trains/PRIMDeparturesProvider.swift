import Foundation

public enum NextTrainsError: Error, Equatable, Sendable {
    case unreachable
    case keyRejected
    case quotaExceeded
    case serviceFailure
}

public protocol DeparturesProvider: Sendable {
    func departures(at stations: [Station]) async throws -> [Departure]
}

public struct PRIMDeparturesProvider: DeparturesProvider {
    public static let endpoint = URL(string: "https://prim.iledefrance-mobilites.fr/marketplace/stop-monitoring")!
    static let timeout: TimeInterval = 15

    private let apiKey: String
    private let httpClient: any HTTPClient

    public init(apiKey: String, httpClient: any HTTPClient = URLSession.shared) {
        self.apiKey = apiKey
        self.httpClient = httpClient
    }

    struct StopRequest: Equatable {
        let monitoringRef: String
        var lineCodes: Set<String>
    }

    public func departures(at stations: [Station]) async throws -> [Departure] {
        let stopRequests = Self.stopRequests(for: stations)
        let results = await withTaskGroup(of: Result<[MonitoredVisit], any Error>.self) { group in
            for stopRequest in stopRequests {
                group.addTask {
                    do {
                        return .success(try await visits(at: stopRequest.monitoringRef).compactMap {
                            Self.visit($0, askedBy: stopRequest)
                        })
                    } catch {
                        return .failure(error)
                    }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        try Task.checkCancellation()

        let visits = results.compactMap { try? $0.get() }.flatMap(\.self)
        let departures = Self.departures(from: visits, at: stations)
        let firstError = results.lazy.compactMap { result -> (any Error)? in
            if case .failure(let error) = result { error } else { nil }
        }.first
        if departures.isEmpty, let firstError {
            throw firstError
        }
        return departures
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
        let linesByCode = Dictionary(
            stations.flatMap { station in
                station.lines.compactMap { line in
                    line.primLineCode.map { ($0, (line: line, stationKey: StationCatalog.searchKey(station.name))) }
                }
            },
            uniquingKeysWith: { first, _ in first }
        )
        var seenJourneys: Set<String> = []
        return visits.compactMap { visit in
            guard let (line, stationKey) = PRIMStopReference.lineCode(fromLineRef: visit.lineRef)
                    .flatMap({ linesByCode[$0] }),
                  visit.destinationRef == nil || visit.destinationRef != visit.monitoringRef,
                  StationCatalog.searchKey(visit.destinationName) != stationKey
            else {
                return nil
            }
            let journeyKey = visit.journeyRef.map { "\(line.mode)-\(line.name)-\($0)" }
                ?? "\(line.mode)-\(line.name)-\(visit.destinationName)-\(visit.time.timeIntervalSince1970)"
            guard seenJourneys.insert(journeyKey).inserted else {
                return nil
            }
            return Departure(
                line: line,
                destination: visit.destinationName,
                time: visit.time,
                quayRef: visit.quayRef,
                directionRef: visit.directionRef
            )
        }
    }

    func request(for monitoringRef: String) -> URLRequest {
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "MonitoringRef", value: monitoringRef)]
        var request = URLRequest(url: components.url!, timeoutInterval: Self.timeout)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func visits(at monitoringRef: String) async throws -> [MonitoredVisit] {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await httpClient.data(for: request(for: monitoringRef))
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw NextTrainsError.unreachable
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case .some(200..<300):
            break
        case .some(401), .some(403):
            throw NextTrainsError.keyRejected
        case .some(429):
            throw NextTrainsError.quotaExceeded
        default:
            throw NextTrainsError.serviceFailure
        }

        do {
            return try StopMonitoringResponse.visits(from: data)
        } catch {
            throw NextTrainsError.serviceFailure
        }
    }
}
