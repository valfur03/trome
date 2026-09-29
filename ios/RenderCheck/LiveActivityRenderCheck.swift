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
    }

    static let surfaces = [
        Surface(name: "lock17", width: 373, isIsland: false, heightLimits: ["L": 160, "XXXL": 195]),
        Surface(name: "lockSE", width: 355, isIsland: false, heightLimits: ["L": 160, "XXXL": 195]),
        Surface(name: "island17", width: 370, isIsland: true, heightLimits: ["L": 87])
    ]
    static let sizes: [(name: String, size: DynamicTypeSize)] = [("L", .large), ("XXXL", .xxxLarge)]
    static let imageStations = [
        "Saint-Lazare", "Châtelet - Les Halles", "Châtelet", "Place de Clichy", "Cité Universitaire",
        "Sartrouville", "Abbesses", "Opéra", "Boigneville", "Haussmann Saint-Lazare",
        "Avenue du Président Kennedy Maison de Radio France", "Saint-Quentin en Yvelines - Montigny-le-Bretonneux",
        "Nation", "République"
    ]
    static let maxPages = 12

    func testRenderEveryStationPage() async throws {
        let started = Date()
        let catalog = try StationCatalog.bundled()
        let fake = try XCTUnwrap(FakeDeparturesProvider.ifAsked(by: ["--fake-trains"]))
        let outDir = try outputDirectory()
        let missing = Self.imageStations.filter { name in !catalog.stations.contains { $0.name == name } }
        XCTAssertEqual(missing, [], "Stations of the image set that the station list no longer has")
        var rows = ["station,page,stale,surface,size,height,limit,over"]
        var renders = 0
        for station in catalog.stations {
            let hub = catalog.hubStations(of: station)
            let departures = try await fake.departures(at: hub)
            let now = Date()
            let board = DepartureBoard(departures: departures, stations: hub, now: now)
            let savesImages = Self.imageStations.contains(station.name)
            var index = 0
            var page = 0
            repeat {
                let state = StationActivityAttributes.ContentState(
                    station: station,
                    trains: .departures(board, updatedAt: now),
                    now: now,
                    firstLineIndex: index
                )
                for isStale in [false, true] {
                    for surface in Self.surfaces {
                        for size in Self.sizes {
                            let image = try render(state, isStale: isStale, on: surface, at: size.size, big: savesImages)
                            renders += 1
                            let height = image.size.height
                            let limit = surface.heightLimits[size.name]
                            let over = limit.map { height > $0 + 0.5 } ?? false
                            let limitText = limit.map { "\($0)" } ?? ""
                            rows.append(
                                "\"\(station.name)\",\(page),\(isStale),\(surface.name),\(size.name),"
                                    + "\(height),\(limitText),\(over)"
                            )
                            if savesImages, let data = image.pngData() {
                                let stale = isStale ? "-stale" : ""
                                let file = "\(station.name)-p\(page)\(stale)-\(surface.name)-\(size.name).png"
                                    .replacingOccurrences(of: " ", with: "_")
                                    .replacingOccurrences(of: "/", with: "_")
                                try data.write(to: outDir.appendingPathComponent(file))
                            }
                        }
                    }
                }
                guard let linesPage = state.trains.linesPage else { break }
                index = linesPage.nextFirstIndex
                page += 1
            } while index != 0 && page < Self.maxPages
        }
        try rows.joined(separator: "\n").write(
            to: outDir.appendingPathComponent("heights.csv"), atomically: true, encoding: .utf8
        )
        let seconds = Int(Date().timeIntervalSince(started))
        print("RENDER-CHECK stations=\(catalog.stations.count) renders=\(renders) seconds=\(seconds)")
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

    private func render(
        _ state: StationActivityAttributes.ContentState,
        isStale: Bool,
        on surface: Surface,
        at size: DynamicTypeSize,
        big: Bool
    ) throws -> UIImage {
        let content = Group {
            if surface.isIsland {
                ExpandedIslandBottomRegion(state: state, isStale: isStale)
            } else {
                LockScreenView(state: state, isStale: isStale)
            }
        }
        .frame(width: surface.width)
        .background(Color.black)
        .foregroundStyle(.white)
        .environment(\.dynamicTypeSize, size)
        .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        let proposedHeight = surface.heightLimits["L"]
        renderer.proposedSize = ProposedViewSize(width: surface.width, height: proposedHeight)
        renderer.scale = big ? 3 : 1
        return try XCTUnwrap(renderer.uiImage)
    }
}
