import Foundation
import Testing
@testable import RATPCore

extension PRIMDeparturesProviderTests {
    @Test(arguments: [("Saint-Lazare", 16, 5), ("Châtelet", 11, 2), ("Abbesses", 2, 1)])
    func asksOncePerStopAreaOfTheStationsOfAHub(name: String, stopsBefore: Int, calls: Int) throws {
        let catalog = try StationCatalog.bundled()
        let station = try #require(catalog.stations.first { $0.name == name })
        let hub = catalog.hubStations(of: station)

        let monitoringRefs = PRIMDeparturesProvider.stopRequests(for: hub).map(\.monitoringRef)

        #expect(Set(hub.flatMap(\.lines).flatMap(\.stopIds)).count == stopsBefore)
        #expect(monitoringRefs.count == calls)
        #expect(Set(monitoringRefs).count == calls)
    }

    @Test func asksOncePerStopAreaOfEveryMetroStation() throws {
        let stations = try StationCatalog.bundled().stations

        for station in stations {
            let stopAreas = Set(station.lines.flatMap { $0.mode == .metro ? $0.stopAreaIds : $0.stopIds })
            #expect(station.lines.allSatisfy { $0.mode != .metro || !$0.stopAreaIds.isEmpty }, "\(station.name)")
            #expect(PRIMDeparturesProvider.stopRequests(for: [station]).count == stopAreas.count, "\(station.name)")
        }
    }

    @Test func keepsOnlyTheLinesAskedForAtAStopAreaOfAHub() {
        let stopRequest = PRIMDeparturesProvider.StopRequest(
            monitoringRef: "STIF:StopArea:SP:42155:",
            lineCodes: ["C01382"]
        )
        let visits = ["STIF:Line::C01382:", "STIF:Line::C01373:"].map {
            MonitoredVisit(
                monitoringRef: "STIF:StopPoint:Q:22059:",
                lineRef: $0,
                destinationRef: nil,
                destinationName: "Somewhere",
                journeyRef: nil,
                time: Fixture.date("2026-09-26T10:02:00Z")
            )
        }

        #expect(visits.compactMap { PRIMDeparturesProvider.visit($0, askedBy: stopRequest) }.map(\.lineRef) == [
            "STIF:Line::C01382:"
        ])
    }

    @Test func showsTheSameTrainsFromTheStopAreaAsFromEachQuay() async throws {
        let stopAreaAnswer = try Fixture.data("stop-monitoring-abbesses-stop-area")
        let (byStopArea, _) = provider { _ in (stopAreaAnswer, 200) }
        let (byQuay, _) = provider { request in
            (try Self.answer(stopAreaAnswer, onlyAt: monitoringRef(of: request) ?? ""), 200)
        }

        let fromStopArea = try await byStopArea.departures(at: [abbesses])
        let fromQuays = try await byQuay.departures(at: [abbessesByQuay])

        #expect(fromStopArea.count == 4)
        #expect(fromStopArea.map(Self.shown) == fromQuays.sorted { $0.time < $1.time }.map(Self.shown))
        #expect(
            LineDirections.directions(of: line12, at: abbesses, from: fromStopArea)
                == LineDirections.directions(of: line12ByQuay, at: abbessesByQuay, from: fromQuays)
        )
    }

    static func shown(_ departure: Departure) -> String {
        "\(departure.line.displayName) \(departure.destination) \(departure.time) \(departure.quayRef ?? "-")"
    }

    static func answer(_ stopAreaAnswer: Data, onlyAt quay: String) throws -> Data {
        var root = try #require(try JSONSerialization.jsonObject(with: stopAreaAnswer) as? [String: Any])
        var siri = try #require(root["Siri"] as? [String: Any])
        var service = try #require(siri["ServiceDelivery"] as? [String: Any])
        var deliveries = try #require(service["StopMonitoringDelivery"] as? [[String: Any]])
        let visits = try #require(deliveries[0]["MonitoredStopVisit"] as? [[String: Any]])
        deliveries[0]["MonitoredStopVisit"] = visits.filter {
            ($0["MonitoringRef"] as? [String: Any])?["value"] as? String == quay
        }
        service["StopMonitoringDelivery"] = deliveries
        siri["ServiceDelivery"] = service
        root["Siri"] = siri
        return try JSONSerialization.data(withJSONObject: root)
    }

    @Test func splitsTheTrainsOfAMetroStopAreaByDestinationWhenPRIMTellsNoQuay() async throws {
        let answer = try #require(String(bytes: Fixture.data("stop-monitoring-abbesses-stop-area"), encoding: .utf8))
            .replacingOccurrences(of: "\"STIF:StopPoint:Q:463116:\"", with: "\"STIF:StopArea:SP:42155:\"")
            .replacingOccurrences(of: "\"STIF:StopPoint:Q:22059:\"", with: "\"STIF:StopArea:SP:42155:\"")
        let (provider, _) = provider { _ in (Data(answer.utf8), 200) }

        let departures = try await provider.departures(at: [abbesses])

        #expect(departures.allSatisfy { $0.quayRef == nil })
        #expect(LineDirections.directions(of: line12, at: abbesses, from: departures) == [
            LineDirection(label: "Mairie d'Aubervilliers", times: [
                Fixture.date("2026-09-26T10:04:00Z"),
                Fixture.date("2026-09-26T10:09:30Z")
            ]),
            LineDirection(label: "Mairie d'Issy", times: [
                Fixture.date("2026-09-26T10:02:30Z"),
                Fixture.date("2026-09-26T10:07:00Z")
            ])
        ])
    }
}
