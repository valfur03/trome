import Testing
@testable import RATPCore

struct LocationQuestionsRulesTests {
    @Test func asksWhileUsingFirstWhenTheRiderWasNeverAsked() {
        var rules = LocationQuestionsRules()

        #expect(rules.start(access: .notDecided) == .askWhileUsing)
        #expect(rules.isAskingWhileUsing)
    }

    @Test(arguments: [LocationAccess.denied, .whileUsing, .always])
    func asksNothingWhenTheRiderAlreadyAnswered(access: LocationAccess) {
        var rules = LocationQuestionsRules()

        #expect(rules.start(access: access) == nil)
        #expect(!rules.isAsking)
    }

    @Test func asksNothingMoreWhileAQuestionIsOpen() {
        var rules = askedWhileUsing()

        #expect(rules.start(access: .notDecided) == nil)
    }

    @Test func asksAlwaysRightAfterWhileUsingWhenTheAppIsActive() {
        var rules = askedWhileUsing()

        #expect(rules.handle(.accessChanged(.whileUsing, appIsActive: true)) == .askAlways)
        #expect(!rules.isAskingWhileUsing)
        #expect(rules.isAskingAlways)
    }

    @Test func asksAlwaysOnceTheFirstQuestionHasClosed() {
        var rules = askedWhileUsing()

        #expect(rules.handle(.accessChanged(.whileUsing, appIsActive: false)) == nil)
        #expect(!rules.isAskingWhileUsing)
        #expect(rules.isAsking)
        #expect(rules.handle(.appBecameActive) == .askAlways)
    }

    @Test(arguments: [LocationAccess.denied, .always])
    func asksNoSecondQuestionAfterAnotherAnswer(access: LocationAccess) {
        var rules = askedWhileUsing()

        #expect(rules.handle(.accessChanged(access, appIsActive: false)) == nil)
        #expect(rules.handle(.appBecameActive) == nil)
        #expect(!rules.isAsking)
    }

    @Test func waitsWhileTheFirstQuestionIsOpen() {
        var rules = askedWhileUsing()

        #expect(rules.handle(.accessChanged(.notDecided, appIsActive: true)) == nil)
        #expect(rules.handle(.appResignedActive) == nil)
        #expect(rules.handle(.appBecameActive) == nil)
        #expect(rules.isAskingWhileUsing)
    }

    @Test func endsWhenTheRiderChangesToAlways() {
        var rules = askedAlways()

        #expect(rules.handle(.accessChanged(.always, appIsActive: true)) == nil)
        #expect(!rules.isAsking)
    }

    @Test func endsWhenTheRiderKeepsWhileUsing() {
        var rules = askedAlways()

        #expect(rules.handle(.appResignedActive) == nil)
        #expect(rules.isAskingAlways)
        #expect(rules.handle(.appBecameActive) == nil)
        #expect(!rules.isAsking)
    }

    @Test func keepsWaitingWhenTheAppBecomesActiveWithoutClosingTheQuestion() {
        var rules = askedAlways()

        #expect(rules.handle(.appBecameActive) == nil)
        #expect(rules.handle(.accessChanged(.whileUsing, appIsActive: true)) == nil)
        #expect(rules.isAskingAlways)
    }

    @Test func endsWhenTheAlwaysQuestionTimesOut() {
        var rules = askedAlways()

        #expect(rules.handle(.alwaysQuestionTimedOut) == nil)
        #expect(!rules.isAsking)
    }

    @Test func endsWhenTheAppGoesToTheBackground() {
        var rules = askedAlways()

        #expect(rules.handle(.appEnteredBackground) == nil)
        #expect(!rules.isAsking)
    }

    @Test func stopsHoldingTheAuthorizationRequestsWhenTheAppGoesToTheBackgroundDuringTheFirstQuestion() {
        var rules = askedWhileUsing()
        #expect(rules.keepsAuthorizationRequestsWaiting)

        #expect(rules.handle(.appEnteredBackground) == nil)

        #expect(!rules.keepsAuthorizationRequestsWaiting)
        #expect(rules.isAskingWhileUsing)
    }

    @Test func stillAsksAlwaysWhenTheRiderAnswersTheFirstQuestionAfterABackgroundTrip() {
        var rules = askedWhileUsing()
        _ = rules.handle(.appEnteredBackground)
        _ = rules.handle(.appBecameActive)

        #expect(rules.handle(.accessChanged(.whileUsing, appIsActive: true)) == .askAlways)
        #expect(rules.isAskingAlways)
    }

    @Test func ignoresEventsWhenItAsksNothing() {
        var rules = LocationQuestionsRules()

        #expect(rules.handle(.accessChanged(.whileUsing, appIsActive: true)) == nil)
        #expect(rules.handle(.appBecameActive) == nil)
        #expect(!rules.isAsking)
    }

    private func askedWhileUsing() -> LocationQuestionsRules {
        var rules = LocationQuestionsRules()
        _ = rules.start(access: .notDecided)
        return rules
    }

    private func askedAlways() -> LocationQuestionsRules {
        var rules = askedWhileUsing()
        _ = rules.handle(.accessChanged(.whileUsing, appIsActive: true))
        return rules
    }
}
