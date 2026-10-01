import Foundation
import Testing
@testable import RATPCore

extension StationActivityContentTests {
    private var chateletLesHalles: Station {
        Station(
            id: "IDFM:monomodalStopPlace:45102",
            name: "Châtelet - Les Halles",
            coordinate: Coordinate(48.861745, 2.346977),
            lines: [TransitLine(mode: .rer, name: "A", stopIds: ["IDFM:monomodalStopPlace:45102"])]
        )
    }

    private func rerATrains(at now: Date, trainAtTheStop: String? = nil) throws -> [LineDirection.Train] {
        var data = try Fixture.data("stop-monitoring-chatelet-rer")
        if let destination = trainAtTheStop {
            data = try answer(data, withTheTrainTo: destination, atTheStop: true)
        }
        let visits = try StopMonitoringResponse.visits(from: data)
        let departures = PRIMDeparturesProvider.departures(from: visits, at: [chateletLesHalles])
        let trains = NextTrainsState.departures(
            DepartureBoard(departures: departures, stations: [chateletLesHalles], now: now),
            updatedAt: now
        )
        let content = ContentState(station: chateletLesHalles, trains: trains, now: now)
        return (content.trains.linesPage?.lines ?? []).flatMap(\.directions).flatMap(\.trains)
    }

    private func answer(_ data: Data, withTheTrainTo destination: String, atTheStop: Bool) throws -> Data {
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var siri = try #require(json["Siri"] as? [String: Any])
        var delivery = try #require(siri["ServiceDelivery"] as? [String: Any])
        var monitoring = try #require(delivery["StopMonitoringDelivery"] as? [[String: Any]])
        var visits = try #require(monitoring[0]["MonitoredStopVisit"] as? [[String: Any]])
        for index in visits.indices {
            var journey = try #require(visits[index]["MonitoredVehicleJourney"] as? [String: Any])
            let names = try #require(journey["DestinationName"] as? [[String: Any]])
            guard names.first?["value"] as? String == destination else { continue }
            var call = try #require(journey["MonitoredCall"] as? [String: Any])
            call["VehicleAtStop"] = atTheStop
            journey["MonitoredCall"] = call
            visits[index]["MonitoredVehicleJourney"] = journey
        }
        monitoring[0]["MonitoredStopVisit"] = visits
        delivery["StopMonitoringDelivery"] = monitoring
        siri["ServiceDelivery"] = delivery
        json["Siri"] = siri
        return try JSONSerialization.data(withJSONObject: json)
    }

    @Test func showsAnRERTrainThatLeavesInOneMinuteOrMoreAsAWaitInMinutes() throws {
        let now = Fixture.date("2026-09-27T08:00:30Z")

        let trains = try rerATrains(at: now)

        #expect(trains.map(\.destination) == ["Saint-Germain-en-Laye", "Boissy-Saint-Léger"])
        #expect(trains.map(\.status) == [nil, nil])
        #expect(trains.map { $0.countdownMinutes(at: now) } == [3, 2])
    }

    @Test func saysAnRERTrainThatLeavesInLessThanOneMinuteIsApproaching() throws {
        let trains = try rerATrains(at: Fixture.date("2026-09-27T08:01:00.5Z"))

        #expect(trains.first { $0.destination == "Boissy-Saint-Léger" }?.status == .approaching)
        #expect(trains.first { $0.destination == "Saint-Germain-en-Laye" }?.status == nil)
    }

    @Test func saysAnRERTrainIsAtThePlatformOnlyWhenPRIMSaysItIsAtTheStop() throws {
        let now = Fixture.date("2026-09-27T08:01:30Z")

        let atTheStop = try rerATrains(at: now, trainAtTheStop: "Boissy-Saint-Léger")
        let notSaid = try rerATrains(at: now)

        #expect(atTheStop.first { $0.destination == "Boissy-Saint-Léger" }?.status == .atPlatform)
        #expect(notSaid.first { $0.destination == "Boissy-Saint-Léger" }?.status == .approaching)
    }

    @Test func neverShowsAnRERTrainThatHasLeft() throws {
        let trains = try rerATrains(at: Fixture.date("2026-09-27T08:02:00Z"))

        #expect(!trains.contains { $0.destination == "Boissy-Saint-Léger" })
        #expect(trains.map(\.destination) == ["Saint-Germain-en-Laye"])
    }
}
