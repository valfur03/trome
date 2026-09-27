import Foundation

public struct LineEnds: Hashable, Sendable {
    public let first: [String]
    public let second: [String]
    let branchStations: [String: [String]]

    public init(first: [String], second: [String], branchStations: [String: [String]] = [:]) {
        self.first = first
        self.second = second
        self.branchStations = branchStations
    }

    public var sides: [[String]] {
        [first, second]
    }

    func reachableEnds(of side: [String], from stationName: String) -> [String] {
        let stationKey = StationCatalog.searchKey(stationName)
        let branchEnd = side.first { end in
            branchStations[end, default: []].contains { StationCatalog.searchKey($0) == stationKey }
        }
        return branchEnd.map { [$0] } ?? side
    }
}

extension TransitLine {
    private static let lineEnds: [String: LineEnds] = [
        "metro-1": LineEnds(first: ["La Défense"], second: ["Château de Vincennes"]),
        "metro-2": LineEnds(first: ["Porte Dauphine"], second: ["Nation"]),
        "metro-3": LineEnds(first: ["Pont de Levallois - Bécon"], second: ["Gallieni"]),
        "metro-3bis": LineEnds(first: ["Gambetta"], second: ["Porte des Lilas"]),
        "metro-4": LineEnds(first: ["Porte de Clignancourt"], second: ["Bagneux - Lucie Aubrac"]),
        "metro-5": LineEnds(first: ["Bobigny - Pablo Picasso"], second: ["Place d'Italie"]),
        "metro-6": LineEnds(first: ["Charles de Gaulle - Étoile"], second: ["Nation"]),
        "metro-7": LineEnds(
            first: ["La Courneuve - 8 Mai 1945"],
            second: ["Mairie d'Ivry", "Villejuif - Louis Aragon"],
            branchStations: [
                "Mairie d'Ivry": ["Porte d'Italie", "Porte de Choisy", "Porte d'Ivry", "Pierre et Marie Curie"],
                "Villejuif - Louis Aragon": [
                    "Le Kremlin-Bicêtre",
                    "Villejuif Léo Lagrange",
                    "Villejuif Paul Vaillant-Couturier"
                ]
            ]
        ),
        "metro-7bis": LineEnds(first: ["Louis Blanc"], second: ["Pré-Saint-Gervais"]),
        "metro-8": LineEnds(first: ["Balard"], second: ["Pointe du Lac"]),
        "metro-9": LineEnds(first: ["Pont de Sèvres"], second: ["Mairie de Montreuil"]),
        "metro-10": LineEnds(first: ["Boulogne Pont de Saint-Cloud"], second: ["Gare d'Austerlitz"]),
        "metro-11": LineEnds(first: ["Châtelet"], second: ["Rosny-Bois-Perrier"]),
        "metro-12": LineEnds(first: ["Mairie d'Aubervilliers"], second: ["Mairie d'Issy"]),
        "metro-13": LineEnds(
            first: ["Saint-Denis - Université", "Asnières - Gennevilliers - Les Courtilles"],
            second: ["Châtillon - Montrouge"],
            branchStations: [
                "Saint-Denis - Université": [
                    "Guy Môquet",
                    "Porte de Saint-Ouen",
                    "Garibaldi",
                    "Mairie de Saint-Ouen",
                    "Carrefour Pleyel",
                    "Saint-Denis - Porte de Paris",
                    "Basilique de Saint-Denis"
                ],
                "Asnières - Gennevilliers - Les Courtilles": [
                    "Brochant",
                    "Porte de Clichy",
                    "Mairie de Clichy",
                    "Gabriel Péri",
                    "Les Agnettes"
                ]
            ]
        ),
        "metro-14": LineEnds(first: ["Saint-Denis - Pleyel"], second: ["Aéroport d'Orly"])
    ]

    public var ends: LineEnds? {
        Self.lineEnds["\(mode.rawValue)-\(name)"]
    }
}
