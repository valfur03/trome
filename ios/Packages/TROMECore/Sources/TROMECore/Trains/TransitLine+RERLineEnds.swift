import Foundation

extension TransitLine {
    private static let rerCVersaillesBranch = [
        "Javel",
        "Pont du Garigliano - Hôpital Européen G. Pompidou",
        "Issy - Val de Seine",
        "Issy",
        "Meudon Val Fleury",
        "Chaville - Vélizy",
        "Viroflay Rive Gauche"
    ]

    private static let rerCJuvisyBranch = [
        "Villeneuve-le-Roi",
        "Ablon",
        "Athis-Mons",
        "Juvisy",
        "Savigny-sur-Orge",
        "Épinay-sur-Orge",
        "Sainte-Geneviève-des-Bois",
        "Saint-Michel-sur-Orge",
        "Brétigny"
    ]

    private static let rerDCorbeilBranch = [
        "Vigneux-sur-Seine",
        "Juvisy",
        "Viry-Châtillon",
        "Ris-Orangis",
        "Grand Bourg",
        "Évry - Val de Seine",
        "Grigny Centre",
        "Orangis Bois de l'Épine",
        "Évry - Courcouronnes",
        "Le Bras de Fer",
        "Corbeil-Essonnes"
    ]

    private static let rerAEnds = LineEnds(
        first: ["Saint-Germain-en-Laye", "Cergy le Haut", "Poissy"],
        second: ["Boissy-Saint-Léger", "Marne-la-Vallée - Chessy"],
        branchStations: [
            "Saint-Germain-en-Laye": [
                "Nanterre - Ville",
                "Rueil-Malmaison",
                "Chatou - Croissy",
                "Le Vésinet - Centre",
                "Le Vésinet - Le Pecq"
            ],
            "Cergy le Haut": [
                "Nanterre Université",
                "Houilles - Carrières-sur-Seine",
                "Sartrouville",
                "Maisons-Laffitte",
                "Achères Ville",
                "Conflans Fin d'Oise",
                "Neuville - Université",
                "Cergy Préfecture",
                "Cergy Saint-Christophe"
            ],
            "Poissy": [
                "Nanterre Université",
                "Houilles - Carrières-sur-Seine",
                "Sartrouville",
                "Maisons-Laffitte",
                "Achères Grand Cormier"
            ],
            "Boissy-Saint-Léger": [
                "Fontenay-sous-Bois",
                "Nogent-sur-Marne",
                "Joinville-le-Pont",
                "Saint-Maur - Créteil",
                "Le Parc de Saint-Maur",
                "Champigny",
                "La Varenne - Chennevières",
                "Sucy - Bonneuil"
            ],
            "Marne-la-Vallée - Chessy": [
                "Val de Fontenay",
                "Neuilly-Plaisance",
                "Bry-sur-Marne",
                "Noisy-le-Grand - Mont d'Est",
                "Noisy - Champs",
                "Noisiel",
                "Lognes",
                "Torcy",
                "Bussy-Saint-Georges",
                "Val d'Europe"
            ]
        ],
        trunkStations: [
            "Nanterre - Préfecture",
            "La Défense",
            "Charles de Gaulle - Étoile",
            "Auber",
            "Châtelet - Les Halles",
            "Gare de Lyon",
            "Nation",
            "Vincennes"
        ]
    )

    private static let rerBEnds = LineEnds(
        first: ["Aéroport Charles de Gaulle 2 TGV", "Mitry - Claye"],
        second: ["Robinson", "Saint-Rémy-lès-Chevreuse"],
        branchStations: [
            "Aéroport Charles de Gaulle 2 TGV": [
                "Sevran - Beaudottes",
                "Villepinte",
                "Parc des Expositions",
                "Aéroport Charles de Gaulle 1"
            ],
            "Mitry - Claye": ["Sevran - Livry", "Vert-Galant", "Villeparisis - Mitry-le-Neuf"],
            "Robinson": ["Sceaux", "Fontenay-aux-Roses"],
            "Saint-Rémy-lès-Chevreuse": [
                "Parc de Sceaux",
                "La Croix de Berny",
                "Antony",
                "Fontaine Michalon",
                "Les Baconnets",
                "Massy - Verrières",
                "Massy - Palaiseau",
                "Palaiseau",
                "Palaiseau - Villebon",
                "Lozère",
                "Le Guichet",
                "Orsay - Ville",
                "Bures-sur-Yvette",
                "La Hacquinière",
                "Gif-sur-Yvette",
                "Courcelle-sur-Yvette"
            ]
        ],
        otherNames: ["Aéroport Charles de Gaulle 2 TGV": ["Aéroport Charles de Gaulle 2"]]
    )

    private static let rerCEnds = LineEnds(
        first: ["Pontoise", "Versailles Château Rive Gauche", "Saint-Quentin en Yvelines - Montigny-le-Bretonneux"],
        second: ["Dourdan la Forêt", "Saint-Martin d'Étampes", "Massy - Palaiseau"],
        branchStations: [
            "Pontoise": [
                "Saint-Ouen-l'Aumône",
                "Saint-Ouen-l'Aumône Liesse",
                "Pierrelaye",
                "Montigny - Beauchamp",
                "Franconville - Le Plessis-Bouchard",
                "Cernay",
                "Ermont - Eaubonne",
                "Saint-Gratien",
                "Épinay-sur-Seine",
                "Gennevilliers",
                "Les Grésillons",
                "Saint-Ouen",
                "Porte de Clichy",
                "Péreire Levallois",
                "Neuilly - Porte Maillot",
                "Avenue Foch",
                "Avenue Henri Martin",
                "Boulainvilliers",
                "Avenue du Président Kennedy Maison de Radio France"
            ],
            "Versailles Château Rive Gauche": rerCVersaillesBranch + ["Porchefontaine"],
            "Saint-Quentin en Yvelines - Montigny-le-Bretonneux": rerCVersaillesBranch + [
                "Versailles Chantiers",
                "Saint-Cyr"
            ],
            "Dourdan la Forêt": rerCJuvisyBranch + [
                "La Norville - Saint-Germain-lès-Arpajon",
                "Arpajon",
                "Égly",
                "Breuillet Village",
                "Breuillet - Bruyères-le-Châtel",
                "Saint-Chéron",
                "Sermaise",
                "Dourdan"
            ],
            "Saint-Martin d'Étampes": rerCJuvisyBranch + [
                "Marolles-en-Hurepoix",
                "Bouray",
                "Lardy",
                "Gare de Chamarande",
                "Étréchy",
                "Étampes"
            ],
            "Massy - Palaiseau": [
                "Les Saules",
                "Orly Ville",
                "Pont de Rungis Aéroport d'Orly",
                "Rungis la Fraternelle",
                "Chemin d'Antony",
                "Massy - Verrières"
            ]
        ],
        otherNames: ["Saint-Quentin en Yvelines - Montigny-le-Bretonneux": ["Saint-Quentin en Yvelines"]]
    )

    private static let rerDEnds = LineEnds(
        first: ["Creil"],
        second: ["Melun", "Malesherbes"],
        branchStations: [
            "Melun": rerDCorbeilBranch + [
                "Montgeron - Crosne",
                "Yerres",
                "Brunoy",
                "Boussy-Saint-Antoine",
                "Combs-la-Ville - Quincy",
                "Lieusaint - Moissy",
                "Savigny-le-Temple - Nandy",
                "Cesson",
                "Le Mée",
                "Le Plessis Chenet",
                "Le Coudray-Montceaux",
                "Saint-Fargeau",
                "Ponthierry - Pringy",
                "Boissise-le-Roi",
                "Vosves"
            ],
            "Malesherbes": rerDCorbeilBranch + [
                "Essonnes Robinson",
                "Villabé",
                "Moulin Galant",
                "Mennecy",
                "Ballancourt",
                "La Ferté-Alais",
                "Boutigny",
                "Maisse",
                "Buno - Gironville",
                "Boigneville"
            ]
        ],
        trunkStations: [
            "Chantilly - Gouvieux",
            "Orry-la-Ville - Coye",
            "La Borne Blanche",
            "Survilliers - Fosses",
            "Louvres",
            "Les Noues",
            "Goussainville",
            "Villiers-le-Bel - Gonesse - Arnouville",
            "Garges - Sarcelles",
            "Pierrefitte - Stains",
            "Saint-Denis",
            "Stade de France Saint-Denis",
            "Gare du Nord",
            "Châtelet - Les Halles",
            "Gare de Lyon",
            "Maisons-Alfort - Alfortville",
            "Le Vert de Maisons",
            "Créteil Pompadour",
            "Villeneuve Triage",
            "Villeneuve-Saint-Georges"
        ]
    )

    private static let rerEEnds = LineEnds(
        first: ["Nanterre-La-Folie"],
        second: ["Chelles - Gournay", "Tournan"],
        branchStations: [
            "Chelles - Gournay": ["Bondy", "Le Raincy - Villemomble - Montfermeil", "Gagny", "Le Chénay Gagny"],
            "Tournan": [
                "Rosny-Bois-Perrier",
                "Rosny-sous-Bois",
                "Val de Fontenay",
                "Nogent - Le Perreux",
                "Les Boullereaux Champigny",
                "Villiers-sur-Marne - Le Plessis-Trévise",
                "Les Yvris Noisy-le-Grand",
                "Émerainville - Pontault-Combault",
                "Roissy-en-Brie",
                "Ozoir-la-Ferrière",
                "Gretz-Armainvilliers"
            ]
        ],
        trunkStations: [
            "La Défense",
            "Neuilly - Porte Maillot",
            "Haussmann Saint-Lazare",
            "Magenta",
            "Rosa Parks",
            "Pantin",
            "Noisy-le-Sec"
        ]
    )

    static let rerLineEnds: [String: LineEnds] = [
        "rer-A": rerAEnds,
        "rer-B": rerBEnds,
        "rer-C": rerCEnds,
        "rer-D": rerDEnds,
        "rer-E": rerEEnds
    ]
}
