import Foundation

/// The answer of the server of the app when it refuses the app token: status 401 with the body
/// `{"error": "unauthorized"}` (`contracts/api/departures-unauthorized.json`).
///
/// Both must match, so that another 401 (a proxy, a network that asks to sign in) or a 403 is a failure
/// like any other, and never tells a rider with a good token to update the app.
/// The server answers a failure of PRIM or an empty budget with 503 and `"out"`, never with 401.
enum AppTokenRefusal {
    static let status = 401
    static let error = "unauthorized"

    private struct Body: Decodable {
        let error: String
    }

    /// Throws `NextTrainsError.appTokenRefused` for this answer of the server of the app.
    static func throwIfRefused(_ response: HTTPURLResponse?, body: Data, from source: TrainDataSource) throws {
        guard case .server = source, isRefusal(response, body: body) else { return }
        throw NextTrainsError.appTokenRefused
    }

    static func isRefusal(_ response: HTTPURLResponse?, body: Data) -> Bool {
        guard response?.statusCode == status, let body = try? JSONDecoder().decode(Body.self, from: body) else {
            return false
        }
        return body.error == error
    }
}
