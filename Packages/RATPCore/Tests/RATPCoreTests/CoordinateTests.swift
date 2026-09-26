import Foundation
import Testing
@testable import RATPCore

struct CoordinateTests {
    @Test(arguments: ["48.8584, 2.2945", "48.8584,2.2945", "48.8584 2.2945", " 48.8584 ; 2.2945 "])
    func parsesLatitudeThenLongitude(text: String) {
        let coordinate = Coordinate(parsing: text)

        #expect(coordinate?.latitude == 48.8584)
        #expect(coordinate?.longitude == 2.2945)
    }

    @Test func parsesNegativeValues() {
        let coordinate = Coordinate(parsing: "-33.8568, -151.2153")

        #expect(coordinate?.latitude == -33.8568)
        #expect(coordinate?.longitude == -151.2153)
    }

    @Test(arguments: ["", "48.8584", "48.8584, 2.2945, 3", "north, east", "48,8584 2,2945", "91, 2", "48, 181"])
    func rejectsInvalidText(text: String) {
        #expect(Coordinate(parsing: text) == nil)
    }

    @Test func formatsWithFiveDecimals() {
        #expect(Coordinate(48.858_437, 2.294_481).formatted == "48.85844, 2.29448")
    }

    @Test func isZeroMetersFromItself() {
        let chatelet = Coordinate(48.8586, 2.3474)

        #expect(chatelet.distance(to: chatelet) == 0)
    }

    @Test func measuresTheDistanceBetweenTwoParisPoints() {
        let eiffelTower = Coordinate(48.8584, 2.2945)
        let notreDame = Coordinate(48.8530, 2.3499)

        #expect(abs(eiffelTower.distance(to: notreDame) - 4_100) < 50)
    }

    @Test func decodesAValidCoordinate() throws {
        let data = Data(#"{"latitude": 48.8584, "longitude": 2.2945}"#.utf8)

        #expect(try JSONDecoder().decode(Coordinate.self, from: data) == Coordinate(48.8584, 2.2945))
    }

    @Test(arguments: [
        #"{"latitude": 91, "longitude": 2.2945}"#,
        #"{"latitude": -91, "longitude": 2.2945}"#,
        #"{"latitude": 48.8584, "longitude": 181}"#,
        #"{"latitude": 48.8584, "longitude": -181}"#
    ])
    func rejectsDecodingAnOutOfRangeCoordinate(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Coordinate.self, from: Data(json.utf8))
        }
    }
}
