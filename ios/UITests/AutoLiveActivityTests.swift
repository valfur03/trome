import XCTest

final class AutoLiveActivityTests: E2ETestCase {
    @MainActor
    func testLiveActivityStartsSwitchesAndStopsByItselfNearStations() {
        let app = makeApp()
        launch(app)
        leaveEveryStation(in: app)

        useFakePosition(atStation: "Abbesses", in: app)
        let lockScreenStation = app.staticTexts["liveActivityStationName"]
        XCTAssertTrue(waitFor(lockScreenStation))
        XCTAssertEqual(lockScreenStation.label, "On the lock screen: Abbesses")
        XCTAssertFalse(app.staticTexts["liveActivityError"].exists)

        useFakePosition(atStation: "Pigalle", in: app)
        waitForLabel("On the lock screen: Pigalle", of: lockScreenStation)
        XCTAssertEqual(app.buttons.matching(identifier: "stopLiveActivity").count, 1)

        tap(app.buttons["testingTools"])
        tap(app.buttons["farFromAnyStation"])
        goBack(in: app)
        XCTAssertTrue(waitForNo(lockScreenStation))
    }
}
