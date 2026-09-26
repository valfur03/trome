public struct TestPlace: Hashable, Identifiable, Sendable {
    public let name: String
    public let lines: [String]
    public let coordinate: Coordinate

    public var id: String {
        name
    }

    public var fakePosition: FakePosition {
        FakePosition(name: name, coordinate: coordinate)
    }
}

public enum TestPlaces {
    public static let stations: [TestPlace] = [
        TestPlace(name: "Aéroport Charles de Gaulle 2", lines: ["RER B"], coordinate: Coordinate(49.00415, 2.57098)),
        TestPlace(name: "Bastille", lines: ["M1", "M5", "M8"], coordinate: Coordinate(48.85292, 2.36905)),
        TestPlace(
            name: "Charles de Gaulle - Étoile",
            lines: ["M1", "M2", "M6", "RER A"],
            coordinate: Coordinate(48.87453, 2.29549)
        ),
        TestPlace(name: "Châtelet", lines: ["M1", "M4", "M7", "M11", "M14"], coordinate: Coordinate(48.85855, 2.34743)),
        TestPlace(
            name: "Châtelet - Les Halles",
            lines: ["RER A", "RER B", "RER D"],
            coordinate: Coordinate(48.86175, 2.34698)
        ),
        TestPlace(name: "Denfert-Rochereau", lines: ["M4", "M6", "RER B"], coordinate: Coordinate(48.83391, 2.33263)),
        TestPlace(
            name: "Gare de Lyon",
            lines: ["M1", "M14", "RER A", "RER D"],
            coordinate: Coordinate(48.84432, 2.37451)
        ),
        TestPlace(
            name: "Gare du Nord",
            lines: ["M4", "M5", "RER B", "RER D"],
            coordinate: Coordinate(48.88052, 2.35692)
        ),
        TestPlace(name: "Invalides", lines: ["M8", "M13", "RER C"], coordinate: Coordinate(48.86085, 2.31417)),
        TestPlace(name: "La Défense", lines: ["M1", "RER A", "RER E"], coordinate: Coordinate(48.89220, 2.23772)),
        TestPlace(name: "La Fourche", lines: ["M13"], coordinate: Coordinate(48.88694, 2.32585)),
        TestPlace(name: "Maison Blanche", lines: ["M7", "M14"], coordinate: Coordinate(48.82186, 2.35879)),
        TestPlace(name: "Marne-la-Vallée - Chessy", lines: ["RER A"], coordinate: Coordinate(48.86980, 2.78248)),
        TestPlace(name: "Nation", lines: ["M1", "M2", "M6", "M9", "RER A"], coordinate: Coordinate(48.84822, 2.39598)),
        TestPlace(name: "Olympiades", lines: ["M14"], coordinate: Coordinate(48.82712, 2.36709)),
        TestPlace(name: "Porte de Clichy", lines: ["M13", "M14", "RER C"], coordinate: Coordinate(48.89464, 2.31367)),
        TestPlace(
            name: "République",
            lines: ["M3", "M5", "M8", "M9", "M11"],
            coordinate: Coordinate(48.86754, 2.36394)
        ),
        TestPlace(name: "Saint-Denis - Pleyel", lines: ["M14"], coordinate: Coordinate(48.91747, 2.34584)),
        TestPlace(
            name: "Saint-Lazare",
            lines: ["M3", "M12", "M13", "M14"],
            coordinate: Coordinate(48.87543, 2.32527)
        ),
        TestPlace(
            name: "Saint-Michel Notre-Dame",
            lines: ["RER B", "RER C"],
            coordinate: Coordinate(48.85302, 2.34496)
        ),
        TestPlace(
            name: "Versailles Château Rive Gauche",
            lines: ["RER C"],
            coordinate: Coordinate(48.79991, 2.13015)
        )
    ]

    public static let farFromAnyStation = FakePosition(
        name: "Far from any station (Fontainebleau forest)",
        coordinate: Coordinate(48.42, 2.63)
    )
}
