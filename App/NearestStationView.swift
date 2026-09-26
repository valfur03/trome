import RATPCore
import SwiftUI
import UIKit

struct NearestStationView: View {
    let state: NearestStationState

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 12) {
            switch state {
            case .idle, .locating:
                ProgressView("Finding the nearest station…")
                    .accessibilityIdentifier("locatingMessage")
            case .permissionUndecided:
                message(
                    "The app needs your location to find the nearest metro or RER station. "
                        + "It will ask again next time.",
                    identifier: "permissionUndecidedMessage"
                )
            case .permissionDenied:
                message(
                    "The app cannot find a station without your location. "
                        + "Turn on location for RATP Activity in Settings.",
                    identifier: "locationDeniedMessage"
                )
                Button("Open Settings", action: openSettings)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("openSettingsButton")
            case .found(let nearby):
                StationSummary(nearby: nearby)
            case .noStationNearby:
                message(
                    "No metro or RER station was found within 2 km of you.",
                    identifier: "noStationNearbyMessage"
                )
            case .locationUnavailable:
                message(
                    "Your position is not available right now. Try again in a moment.",
                    identifier: "locationUnavailableMessage"
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func message(_ text: String, identifier: String) -> some View {
        Text(text)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier(identifier)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

private struct StationSummary: View {
    let nearby: NearbyStation

    private var distance: Measurement<UnitLength> {
        Measurement(value: nearby.distanceMeters, unit: .meters)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("Nearest station")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(nearby.station.name)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("nearestStationName")
            Text(nearby.station.lines.map(\.displayName).joined(separator: " · "))
                .accessibilityIdentifier("nearestStationLines")
            Text(distance, format: .measurement(width: .abbreviated, usage: .road))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("nearestStationDistance")
        }
    }
}
