import XCTest

extension E2ETestCase {
    private struct TapTarget: Equatable, CustomStringConvertible {
        let point: CGPoint
        let card: CGRect

        var isOnTheCard: Bool { card.contains(point) }
        var description: String { "point \(point) on the card \(card)" }
    }

    @MainActor
    func tapOnTheLiveActivity(
        _ button: XCUIElement,
        pointsBelowItsTop: CGFloat? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(waitFor(button), "\(button) did not show", file: file, line: line)
        let (target, lastSeen) = waitUntilStillOnTheCard(tapPoint(on: button, pointsBelowItsTop: pointsBelowItsTop))
        guard let target else {
            XCTFail(
                "\(button) did not stay still on the Live Activity: last seen \(lastSeen.map(\.description) ?? "none")",
                file: file,
                line: line
            )
            return
        }
        springboard.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: target.point.x, dy: target.point.y))
            .tap()
    }

    @MainActor
    private func tapPoint(on button: XCUIElement, pointsBelowItsTop: CGFloat?) -> XCUICoordinate {
        guard let pointsBelowItsTop else {
            return button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        }
        return button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: pointsBelowItsTop))
    }

    @MainActor
    private func waitUntilStillOnTheCard(_ point: XCUICoordinate) -> (still: TapTarget?, lastSeen: TapTarget?) {
        let deadline = Date().addingTimeInterval(UITestTimeout.element)
        var previous: TapTarget?
        var lastSeen: TapTarget?
        repeat {
            let target = (try? liveActivity.snapshot().frame).map { TapTarget(point: point.screenPoint, card: $0) }
            if let target, target.isOnTheCard, target == previous {
                return (target, target)
            }
            previous = target
            lastSeen = target ?? lastSeen
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        } while Date() < deadline
        return (nil, lastSeen)
    }
}
