import Foundation
import Testing
@testable import TROMECore

struct RegionFirstStatesTests {
    @Test func summarizesTheFirstStateOfEachNewAreaInOneLine() {
        var states = RegionFirstStates(expecting: ["a", "b", "c", "d"])

        let taken = [
            states.take(id: "a", label: "Station A", state: .outside, problems: ""),
            states.take(id: "b", label: "Station B", state: .outside, problems: ""),
            states.take(id: "c", label: "area around you", state: .inside, problems: "")
        ]
        let completeBeforeTheLast = states.isComplete
        let tookTheLast = states.take(id: "d", label: "Station D", state: .notWatched, problems: "conditionUnsupported")

        #expect(taken == [true, true, true])
        #expect(!completeBeforeTheLast)
        #expect(tookTheLast)
        #expect(states.isComplete)
        #expect(states.summary == """
            iOS: first state of 4 new areas: 2 outside, inside area around you, \
            1 not watched [conditionUnsupported]
            """)
    }

    @Test func leavesAnEventOfAnAreaThatIsNotNewToItsOwnLine() {
        var states = RegionFirstStates(expecting: ["a"])

        let taken = [
            states.take(id: "b", label: "Station B", state: .inside, problems: ""),
            states.take(id: "a", label: "Station A", state: .outside, problems: ""),
            states.take(id: "a", label: "Station A", state: .inside, problems: "")
        ]

        #expect(taken == [false, true, false])
        #expect(states.summary == "iOS: first state of 1 new areas: 1 outside")
    }

    @Test func saysNothingWhenNoFirstStateCame() {
        #expect(RegionFirstStates(expecting: ["a"]).summary == nil)
    }
}
