import Foundation
import Testing
@testable import TROMECore

/// The background time that iOS still gives the app, as a wake line and the ask of the start say it: a walk reads
/// from it whether iOS was about to suspend the app.
struct BackgroundTimeTests {
    @Test func tellsTheWholeSecondsLeft() {
        #expect(BackgroundTime.line(remaining: 29.9) == "29 s of background time left")
        #expect(BackgroundTime.line(remaining: 0) == "0 s of background time left")
    }

    /// iOS gives `Double.greatestFiniteMagnitude` when the app has no limit, for example on screen.
    @Test func tellsNoLimitForTheHugeNumberOfIOS() {
        #expect(BackgroundTime.line(remaining: .greatestFiniteMagnitude) == "no background time limit")
        #expect(BackgroundTime.line(remaining: .infinity) == "no background time limit")
    }
}
