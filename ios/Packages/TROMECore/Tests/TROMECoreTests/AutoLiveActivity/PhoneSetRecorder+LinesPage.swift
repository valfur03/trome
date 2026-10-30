import Foundation
import Testing
@testable import TROMECore

/// The line page that a rider tapped to on a Live Activity, which the builds before 1.0.0 (4) cannot hold: so this
/// file stays out of the copy that records an older build (`PhoneSetRecorder`).
extension PhoneSetRecorder {
    /// A station with several lines, so that the chosen page is not the first one, which a rider gets anyway.
    static let pageChoiceCase = "chatelet-les-halles-hub"
    /// An identifier as ActivityKit gives it to a Live Activity.
    static let pageChoiceActivityID = "5C3B4F0E-9A27-4D7B-8E61-2F0A1C9D3B72"

    /// The widget reads the choice from the `UserDefaults` of the app group, and the other stores from the standard
    /// ones: both keep the `Data` that a store writes as it is, so one recorded file per key holds what each reads.
    @Test(.enabled(if: output != nil))
    func recordsTheLinePageThatTheRiderTappedTo() async throws {
        let shown = try await Self.trains(of: Self.pageChoiceCase)
        let content = StationActivityAttributes.ContentState(
            station: shown.station,
            trains: shown.trains,
            now: shown.now
        )
        let page = try #require(content.trains.linesPage, "\(Self.pageChoiceCase) shows no page of lines")
        let line = try #require(page.allLines.last, "\(Self.pageChoiceCase) has no line")
        #expect(page.allLines.count > 1, "\(Self.pageChoiceCase): the rider can tap to no other page")
        try record("lines-page-chosen", rider: [
            "linesPageChoice": [
                "contentCase": Self.pageChoiceCase,
                "activityID": Self.pageChoiceActivityID,
                "stationName": content.stationName,
                "line": ["mode": line.mode.rawValue, "name": line.name]
            ]
        ]) { storage in
            let choice = LinesPageChoice(
                activityID: Self.pageChoiceActivityID,
                stationName: content.stationName,
                line: line
            )
            LinesPageChoiceStore(storage: storage).save(choice)
        }
    }
}
