import CoreLocation
import TROMECore

extension PositionFix {
    init?(_ location: CLLocation) {
        guard let coordinate = Coordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        ) else {
            return nil
        }
        self.init(coordinate: coordinate, accuracyMeters: location.horizontalAccuracy, timestamp: location.timestamp)
    }
}
