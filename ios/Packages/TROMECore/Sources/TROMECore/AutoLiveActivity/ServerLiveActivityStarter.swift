import Foundation

/// Asks the server of the app to start the Live Activity of a station on this iPhone, through Apple's push service,
/// with the start token that ActivityKit gave the app (`server/guide/how-it-works.md`, "The start of a Live Activity").
public struct ServerLiveActivityStarter: LiveActivityStarter {
    private let server: TrainServerConfiguration
    private let httpClient: any HTTPClient

    public init(server: TrainServerConfiguration, httpClient: any HTTPClient) {
        self.server = server
        self.httpClient = httpClient
    }

    public func start(stationId: String, startToken: String) async -> LiveActivityStartAnswer {
        do {
            let (data, response) = try await httpClient.data(for: request(stationId: stationId, startToken: startToken))
            guard let response = response as? HTTPURLResponse else { return .noAnswer }
            return LiveActivityStartAnswer(status: response.statusCode, body: data)
        } catch {
            return .noAnswer
        }
    }

    func request(stationId: String, startToken: String) -> URLRequest {
        let url = server.baseURL
            .appending(path: "v1")
            .appending(path: "stations")
            .appending(path: stationId)
            .appending(path: "live-activity")
        var request = URLRequest(url: url, timeoutInterval: TimeInterval(SilentStart.answerLimit.components.seconds))
        request.httpMethod = "POST"
        request.setValue("Bearer \(server.appToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONEncoder().encode(["startToken": startToken])
        return request
    }
}
