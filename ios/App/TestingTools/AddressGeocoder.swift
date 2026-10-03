#if DEBUG
import MapKit
import TROMECore

struct AddressGeocoder {
    struct NotFound: Error {}

    @MainActor
    func fakePosition(for address: String) async throws -> FakePosition {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = address
        request.resultTypes = [.address, .pointOfInterest]
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522),
            latitudinalMeters: 60_000,
            longitudinalMeters: 60_000
        )
        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch let error as MKError where error.code == .placemarkNotFound {
            throw NotFound()
        }
        guard let item = response.mapItems.first else {
            throw NotFound()
        }
        let location = Self.coordinate(of: item)
        guard let coordinate = Coordinate(latitude: location.latitude, longitude: location.longitude) else {
            throw NotFound()
        }
        return FakePosition(name: item.name ?? address, coordinate: coordinate)
    }

    private static func coordinate(of item: MKMapItem) -> CLLocationCoordinate2D {
        if #available(iOS 26, *) {
            item.location.coordinate
        } else {
            item.placemark.coordinate
        }
    }
}
#endif
