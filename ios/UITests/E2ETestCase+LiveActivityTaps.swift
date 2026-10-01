import XCTest

extension E2ETestCase {
    @MainActor
    func tapOnTheLiveActivity(
        _ button: XCUIElement,
        pointsBelowItsTop: CGFloat? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(waitFor(button), "\(button) did not show", file: file, line: line)
        XCTAssertTrue(
            waitUntilStill(button),
            "\(button) kept moving: the Live Activity was still drawing its new content",
            file: file,
            line: line
        )
        if let pointsBelowItsTop {
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                .withOffset(CGVector(dx: 0, dy: pointsBelowItsTop))
                .tap()
        } else {
            button.tap()
        }
    }

    @MainActor
    private func waitUntilStill(_ element: XCUIElement) -> Bool {
        let deadline = Date().addingTimeInterval(UITestTimeout.element)
        var lastFrame: CGRect?
        repeat {
            let frame = element.isHittable ? try? element.snapshot().frame : nil
            if let frame, frame == lastFrame {
                return true
            }
            lastFrame = frame
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        } while Date() < deadline
        return false
    }
}
