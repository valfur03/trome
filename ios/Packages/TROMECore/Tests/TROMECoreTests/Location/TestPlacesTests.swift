import Testing
@testable import TROMECore

struct TestPlacesTests {
    @Test func placesTheFakePositionOfAStationOnTheStation() {
        let chatelet = Station(
            id: "IDFM:71264",
            name: "Châtelet",
            coordinate: Coordinate(48.858_56, 2.347_43),
            lines: [TransitLine(mode: .metro, name: "1")]
        )

        #expect(chatelet.fakePosition == FakePosition(name: "Châtelet", coordinate: Coordinate(48.858_56, 2.347_43)))
    }

    @Test func showsFarFromAnyStationWithFiveDecimals() {
        #expect(TestPlaces.farFromAnyStation.coordinate.formatted == "48.42000, 2.63000")
    }
}
