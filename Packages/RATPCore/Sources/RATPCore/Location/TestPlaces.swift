public enum TestPlaces {
    public static let farFromAnyStation = FakePosition(
        name: "Far from any station (Fontainebleau forest)",
        coordinate: Coordinate(48.42, 2.63)
    )
}

public extension Station {
    var fakePosition: FakePosition {
        FakePosition(name: name, coordinate: coordinate)
    }
}
