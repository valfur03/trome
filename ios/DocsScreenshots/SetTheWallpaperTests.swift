import XCTest

/// Sets the wallpaper of `Wallpaper` as the wallpaper pair (lock screen and Home Screen) of the Simulator.
/// The Simulator has no setting and no `simctl` command for it, so the test does what a person does:
/// a long press on the lock screen opens the wallpaper switcher, where a wallpaper is added from the gallery,
/// or chosen when the switcher already holds it.
///
/// Only `make simulator-wallpaper` runs it, once, through `ios/scripts/wallpaper.sh`:
/// the Simulator keeps the wallpaper, and no picture command adds or deletes one.
/// It runs only when TEST_RUNNER_SET_THE_WALLPAPER is 1, so a plain run of the target changes nothing.
final class SetTheWallpaperTests: XCTestCase {
    private let timeout: TimeInterval = 30
    private let posterPrefix = "posterboard-posteruuid-"

    @MainActor
    private var springboard: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    @MainActor
    private var posterBoard: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.PosterBoard")
    }

    @MainActor
    private var wallpapers: XCUIElementQuery {
        posterBoard.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", posterPrefix))
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// TEST_RUNNER_WALLPAPER_UUID, when set, is the id of the wallpaper in the switcher (its folder on disk):
    /// the test chooses it instead of adding a second copy.
    @MainActor
    func testSetTheWallpaper() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["SET_THE_WALLPAPER"] == "1", "TEST_RUNNER_SET_THE_WALLPAPER is not 1")
        if let uuid = environment["WALLPAPER_UUID"], !uuid.isEmpty {
            choose(posterPrefix + uuid)
        } else {
            add(Wallpaper.galleryID)
        }
        openTheLockScreen()
        keep(XCUIScreen.main.screenshot(), named: "wallpaper")
        XCUIDevice.shared.press(.home)
    }

    /// Adds the wallpaper of the gallery, and sets it as the wallpaper pair.
    @MainActor
    private func add(_ galleryID: String) {
        openTheSwitcher()
        tap(posterBoard.buttons["posterboard-add-button"], "the add button of the wallpaper switcher")
        tapTheTile(galleryID)
        tap(
            posterBoard.buttons.matching(NSPredicate(format: "label IN {'Add', 'Ajouter'}")).firstMatch,
            "the Add button of the wallpaper editor"
        )
        tap(
            posterBoard.buttons.matching(NSPredicate(
                format: "label BEGINSWITH 'Set as Wallpaper Pair' OR label BEGINSWITH 'Définir comme paire'"
            )).firstMatch,
            "the button that sets the wallpaper pair"
        )
        XCUIDevice.shared.press(.home)
    }

    /// Chooses a wallpaper that the switcher already holds.
    @MainActor
    private func choose(_ identifier: String) {
        openTheSwitcher()
        XCTAssertTrue(
            posterBoard.cells[identifier].waitForExistence(timeout: timeout),
            "No wallpaper \(identifier) in the switcher"
        )
        let cell = switcherCell(identifier)
        bringToTheMiddle(cell)
        // A tap on the wallpaper in the middle chooses it and closes the switcher.
        tap(cell, "the wallpaper \(identifier)")
        XCUIDevice.shared.press(.home)
    }

    /// The cell of the wallpaper in the switcher: narrower than the screen, unlike the full-screen cell of the same id.
    @MainActor
    private func switcherCell(_ identifier: String) -> XCUIElement {
        let cells = wallpapers.matching(identifier: identifier).allElementsBoundByIndex
        return cells.first { $0.frame.width < posterBoard.frame.width * 0.9 } ?? cells[0]
    }

    /// Drags the switcher sideways until the wallpaper is the one in the middle.
    @MainActor
    private func bringToTheMiddle(_ wallpaper: XCUIElement) {
        let middle = posterBoard.frame.midX
        for _ in 0..<10 {
            let offset = wallpaper.frame.midX - middle
            guard abs(offset) > 40 else {
                return
            }
            let target = offset > 0 ? 0.2 : 0.8
            let start = posterBoard.coordinate(withNormalizedOffset: CGVector(dx: 1 - target, dy: 0.5))
            let end = posterBoard.coordinate(withNormalizedOffset: CGVector(dx: target, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: end)
            sleep(1)
        }
        XCTFail("The wallpaper \(wallpaper.identifier) did not come to the middle of the switcher")
    }

    /// A long press on the lock screen opens the wallpaper switcher, on the wallpaper in use.
    @MainActor
    private func openTheSwitcher() {
        openTheLockScreen()
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).press(forDuration: 2.5)
        XCTAssertTrue(
            posterBoard.buttons["posterboard-add-button"].waitForExistence(timeout: timeout),
            "The wallpaper switcher did not open"
        )
        sleep(1)
    }

    /// Pulls the Notification Center down from the Home Screen: it shows the lock screen, with its wallpaper.
    @MainActor
    private func openTheLockScreen() {
        XCUIDevice.shared.press(.home)
        sleep(1)
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.001))
        let middle = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7))
        top.press(forDuration: 0.1, thenDragTo: middle)
        XCTAssertTrue(springboard.otherElements["lockscreen-date-view"].waitForExistence(timeout: timeout))
    }

    @MainActor
    private func tap(_ element: XCUIElement, _ what: String) {
        if !element.waitForExistence(timeout: timeout) {
            keep(XCUIScreen.main.screenshot(), named: "no-\(what)")
            XCTFail("No \(what)")
        }
        // A tap on the element itself first checks that it is hittable, and the wallpaper screens of iOS
        // often fail that check: XCTest then runs its interruption handling, after which the element is
        // "no longer valid", and the tap fails. A tap at the middle of its frame skips that check.
        let frame = element.frame
        springboard.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
            .tap()
        // The wallpaper screens of iOS animate for about a second, and ignore a tap in the meantime.
        sleep(2)
    }

    /// Scrolls the gallery until the tile is on screen, then taps it.
    @MainActor
    private func tapTheTile(_ identifier: String) {
        let tile = posterBoard.descendants(matching: .any)[identifier]
        if !tile.waitForExistence(timeout: timeout) {
            keep(XCUIScreen.main.screenshot(), named: "no-tile")
            XCTFail("No tile \(identifier) in the wallpaper gallery")
        }
        let screen = posterBoard.frame
        for _ in 0..<20 {
            let frame = tile.frame
            let from: CGVector
            let target: CGVector
            if frame.minY > screen.maxY - 120 {
                (from, target) = (CGVector(dx: 0.5, dy: 0.8), CGVector(dx: 0.5, dy: 0.45))
            } else if frame.minY < screen.minY + 100 {
                (from, target) = (CGVector(dx: 0.5, dy: 0.3), CGVector(dx: 0.5, dy: 0.6))
            } else if frame.maxX > screen.maxX {
                let row = frame.midY / screen.height
                (from, target) = (CGVector(dx: 0.9, dy: row), CGVector(dx: 0.3, dy: row))
            } else {
                break
            }
            posterBoard.coordinate(withNormalizedOffset: from)
                .press(forDuration: 0.05, thenDragTo: posterBoard.coordinate(withNormalizedOffset: target))
            sleep(1)
        }
        tile.tap()
        // The editor draws the wallpaper before its Add button answers.
        sleep(4)
    }

    @MainActor
    private func keep(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
