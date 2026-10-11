import Foundation

enum ArrivalOutcome: Equatable, Sendable {
    case notified(Station)
    case started(Station)
    case switched(Station)
    case liveActivitiesOff(Station)
    case waitsForTheApp(Station)
    case automaticStartOff(Station)
    case paused(Station, until: Date)
    case alreadyShown(Station)
    case alreadyArrived(Station)
    case left(Station)
    case noStationNear(NearbyStation?)

    /// The station that the outcome is about, if any.
    var station: Station? {
        switch self {
        case .notified(let station), .started(let station), .switched(let station), .liveActivitiesOff(let station),
             .waitsForTheApp(let station), .automaticStartOff(let station), .paused(let station, _),
             .alreadyShown(let station), .alreadyArrived(let station), .left(let station):
            station
        case .noStationNear:
            nil
        }
    }

    var logKey: String {
        guard case .noStationNear(let nearest) = self else { return summary }
        return "noStationNear:\(nearest?.station.id ?? "")"
    }

    var summary: String {
        let arrivalRadius = Int(AutoLiveActivityRules.arrivalRadiusMeters)
        let stopRadius = Int(AutoLiveActivityRules.stopRadiusMeters)
        return switch self {
        case .notified(let station):
            "Notified: \(station.name)"
        case .started(let station):
            "Live Activity started: \(station.name)"
        case .switched(let station):
            "Live Activity switched to \(station.name)"
        case .liveActivitiesOff(let station):
            "No start at \(station.name): Live Activities are off in Settings"
        case .waitsForTheApp(let station):
            "Waits at \(station.name): a system popup covers the app"
        case .automaticStartOff(let station):
            "No notification at \(station.name): automatic start is snoozed or off"
        case .paused(let station, let end):
            "No notification at \(station.name): paused until \(end.formatted(date: .omitted, time: .shortened))"
        case .alreadyShown(let station):
            "No notification at \(station.name): its Live Activity shows"
        case .alreadyArrived(let station):
            "No notification at \(station.name): same arrival as before, until you leave its \(stopRadius) m area"
        case .left(let station):
            "Left \(station.name): iOS says the phone left its \(stopRadius) m area"
        case .noStationNear(let nearest?):
            "No station within \(arrivalRadius) m: nearest is \(nearest.station.name), \(Int(nearest.distanceMeters)) m"
        case .noStationNear(nil):
            "No station within \(arrivalRadius) m"
        }
    }
}
