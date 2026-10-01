import RATPCore
import SwiftUI
import XCTest

@MainActor
final class LiveActivityRenderCheck: XCTestCase {
    struct Surface {
        let name: String
        let width: CGFloat
        let isIsland: Bool
        let heightLimits: [String: CGFloat]

        func heightLimit(of state: StationActivityAttributes.ContentState, at size: String) -> CGFloat? {
            if isIsland, state.trains.linesPage?.showsSeveralLines == true { return nil }
            return heightLimits[size]
        }
    }

    struct Render {
        let station: Station
        let page: Int
        let state: StationActivityAttributes.ContentState
        let isStale: Bool
        let surface: Surface
        let sizeName: String
        let size: DynamicTypeSize
    }

    static let surfaces = [
        Surface(name: "lock17", width: 373, isIsland: false, heightLimits: ["L": 160, "XXXL": 195]),
        Surface(name: "lockSE", width: 355, isIsland: false, heightLimits: ["L": 160, "XXXL": 195]),
        Surface(name: "island17", width: 338, isIsland: true, heightLimits: ["L": 87])
    ]
    static let sizes: [(name: String, size: DynamicTypeSize)] = [("L", .large), ("XXXL", .xxxLarge)]
    static let imageStations = [
        "Saint-Lazare", "Châtelet - Les Halles", "Châtelet", "Place de Clichy", "Cité Universitaire",
        "Sartrouville", "Abbesses", "Opéra", "Boigneville", "Haussmann Saint-Lazare",
        "Avenue du Président Kennedy Maison de Radio France", "Saint-Quentin en Yvelines - Montigny-le-Bretonneux",
        "Nation", "République", "Gare du Nord",
        "Lamarck - Caulaincourt", "Brochant", "Asnières - Gennevilliers - Les Courtilles",
        "École Vétérinaire de Maisons-Alfort", "Chevilly-Larue (Marché International)",
        "Villejuif Paul Vaillant-Couturier", "Boulogne Jean Jaurès", "Pont de Levallois - Bécon", "Pelleport",
        "Botzaris"
    ]
    static let maxPages = 12
    static let scale: CGFloat = 3

    private let renderer = ImageRenderer(content: AnyView(EmptyView()))
    private let recorder = DrawnTextRecorder()
    private var imageTexts: [ImageTexts] = []

    func testRenderEveryStationPage() async throws {
        let started = Date()
        let language = try checkLanguage()
        let catalog = try StationCatalog.bundled()
        let fake = try XCTUnwrap(FakeDeparturesProvider.ifAsked(by: ["--fake-trains"]))
        let outDir = try outputDirectory()
        let missing = Self.imageStations.filter { name in !catalog.stations.contains { $0.name == name } }
        XCTAssertEqual(missing, [], "Stations of the image set that the station list no longer has")
        var rows = ["station,page,stale,surface,size,height,limit,over"]
        for station in catalog.stations {
            let hub = catalog.hubStations(of: station)
            let now = Date()
            let board = DepartureBoard(departures: try await fake.departures(at: hub), stations: hub, now: now)
            var index = 0
            var page = 0
            repeat {
                let state = StationActivityAttributes.ContentState(
                    station: station,
                    trains: .departures(board, updatedAt: now),
                    now: now,
                    firstLineIndex: index
                )
                rows += try drawEveryVariant(of: state, at: station, page: page, into: outDir)
                guard let linesPage = state.trains.linesPage else { break }
                index = linesPage.nextFirstIndex
                page += 1
            } while index != 0 && page < Self.maxPages
        }
        let stripStation = try XCTUnwrap(catalog.stations.first { $0.name == Self.stripStatesStation })
        for (page, state) in Self.stripStates(at: stripStation, now: Date()).enumerated() {
            let pageNumber = Self.firstStripStatesPage + page
            rows += try drawEveryVariant(of: state, at: stripStation, page: pageNumber, into: outDir)
        }
        try rows.joined(separator: "\n").write(
            to: outDir.appendingPathComponent("heights.csv"), atomically: true, encoding: .utf8
        )
        try JSONEncoder().encode(imageTexts).write(to: outDir.appendingPathComponent("texts.json"))
        let seconds = Int(Date().timeIntervalSince(started))
        print(
            "RENDER-CHECK language=\(language) stations=\(catalog.stations.count) renders=\(rows.count - 1)"
                + " seconds=\(seconds)"
        )
    }

    private func checkLanguage() throws -> String {
        let language = try XCTUnwrap(
            ProcessInfo.processInfo.environment["RENDER_LANGUAGE"],
            "Run it with make live-activity-render (it sets RENDER_LANGUAGE)"
        )
        XCTAssertEqual(
            Bundle.main.preferredLocalizations.first, language,
            "The views would draw in another language than \(language)"
        )
        if language == "fr" {
            XCTAssertEqual(
                String(localized: "Today"), "Aujourd’hui",
                "The texts of the widget are not in French: the String Catalog of the widget is not in the host app"
            )
        }
        return language
    }

    private func outputDirectory() throws -> URL {
        let path = try XCTUnwrap(
            ProcessInfo.processInfo.environment["RENDER_OUT"],
            "Run it with make live-activity-render (it sets RENDER_OUT)"
        )
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func drawEveryVariant(
        of state: StationActivityAttributes.ContentState,
        at station: Station,
        page: Int,
        into outDir: URL
    ) throws -> [String] {
        var rows: [String] = []
        for isStale in [false, true] {
            for surface in Self.surfaces {
                for size in Self.sizes {
                    let render = Render(
                        station: station, page: page, state: state, isStale: isStale,
                        surface: surface, sizeName: size.name, size: size.size
                    )
                    rows.append(try draw(render, into: outDir))
                }
            }
        }
        return rows
    }

    private func draw(_ render: Render, into outDir: URL) throws -> String {
        let savesImage = render.station.hubId != nil || Self.imageStations.contains(render.station.name)
        let content = Group {
            if render.surface.isIsland {
                ExpandedIslandBottomRegion(state: render.state, isStale: render.isStale)
            } else {
                LockScreenView(state: render.state, isStale: render.isStale)
            }
        }
        .frame(width: render.surface.width)
        .background(Color.black)
        .foregroundStyle(.white)
        .environment(\.dynamicTypeSize, render.size)
        .environment(\.colorScheme, .dark)
        if savesImage {
            recorder.reset()
            let recorder = recorder
            renderer.content = AnyView(
                content.overlayPreferenceValue(Text.LayoutKey.self) { layouts in
                    GeometryReader { proxy in recorder.record(layouts, in: proxy) }
                }
            )
        } else {
            renderer.content = AnyView(content)
        }
        renderer.proposedSize = ProposedViewSize(
            width: render.surface.width,
            height: render.surface.heightLimit(of: render.state, at: "L")
        )
        renderer.scale = Self.scale
        var height: CGFloat = 0
        if savesImage {
            let image = try XCTUnwrap(renderer.uiImage)
            height = image.size.height
            try XCTUnwrap(image.pngData()).write(to: outDir.appendingPathComponent(imageFile(of: render)))
            imageTexts.append(
                ImageTexts(
                    image: imageFile(of: render), station: render.station.name, page: render.page,
                    isStale: render.isStale, surface: render.surface.name, size: render.sizeName,
                    height: height, drawn: recorder.texts, expected: ExpectedText.all(of: render.state)
                )
            )
        } else {
            renderer.render(rasterizationScale: Self.scale) { size, _ in
                height = (size.height * Self.scale).rounded(.up) / Self.scale
            }
        }
        let limit = render.surface.heightLimit(of: render.state, at: render.sizeName)
        let over = limit.map { height > $0 + 0.5 } ?? false
        let limitText = limit.map { "\($0)" } ?? ""
        return "\"\(render.station.name)\",\(render.page),\(render.isStale),\(render.surface.name),"
            + "\(render.sizeName),\(height),\(limitText),\(over)"
    }

    private func imageFile(of render: Render) -> String {
        let stale = render.isStale ? "-stale" : ""
        return "\(render.station.name)-p\(render.page)\(stale)-\(render.surface.name)-\(render.sizeName).png"
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }
}
