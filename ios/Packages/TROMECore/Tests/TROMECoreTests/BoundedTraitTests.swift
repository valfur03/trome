import Foundation
import Testing

/// Every unit test runs inside the trait `.bounded`, so that a `swift test` by hand on a busy Mac runs at most as many
/// tests at once as the Mac has cores, as `make test` does, and its waits do not run out of time.
@Suite(.bounded)
struct BoundedTraitTests {
    private static let folder = URL(filePath: #filePath).deletingLastPathComponent()

    @Test func everySuiteOfTheTestsHasTheTrait() throws {
        let files = try FileManager.default
            .subpathsOfDirectory(atPath: Self.folder.path())
            .filter { $0.hasSuffix(".swift") }
            .sorted()
            .map { (path: $0, text: try String(contentsOf: Self.folder.appending(path: $0), encoding: .utf8)) }
        #expect(files.count > 100, "The check found too few test files: it reads the wrong folder.")
        let missing = BoundedSuites.missing(in: files)
        #expect(missing.isEmpty, "Put @Suite(.bounded) on these suites: \(missing)")
    }

    @Test func findsASuiteWithoutTheTrait() {
        let missing = BoundedSuites.missing(in: [
            (path: "A.swift", text: "@MainActor\nstruct ATests {\n    @Test func a() {}\n}\n"),
            (path: "B.swift", text: "@Suite(.timeLimit(.minutes(1)))\nstruct BTests {\n    @Test func b() {}\n}\n")
        ])
        #expect(missing == [
            BoundedSuites.Missing(file: "A.swift", line: 2, name: "ATests"),
            BoundedSuites.Missing(file: "B.swift", line: 2, name: "BTests")
        ])
    }

    @Test func findsTheSuiteOfATestInAnExtensionInAnotherFile() {
        let missing = BoundedSuites.missing(in: [
            (path: "A.swift", text: "struct ATests {\n    func helper() {}\n}\n"),
            (path: "A+More.swift", text: "extension ATests {\n    @Test func more() {}\n}\n")
        ])
        #expect(missing == [BoundedSuites.Missing(file: "A.swift", line: 1, name: "ATests")])
    }

    @Test func findsATopLevelTestWithoutTheTrait() {
        let missing = BoundedSuites.missing(in: [(path: "A.swift", text: "@Test func alone() {}\n")])
        #expect(missing == [BoundedSuites.Missing(file: "A.swift", line: 1, name: "alone")])
    }

    @Test func acceptsTheTraitAmongOtherTraitsOnAnySuite() {
        let missing = BoundedSuites.missing(in: [
            (path: "A.swift", text: "@Suite(.timeLimit(.minutes(1)), .bounded)\nstruct A {\n    @Test func a() {}\n}"),
            (path: "B.swift", text: "@MainActor\n@Suite(\n    .bounded\n)\nfinal class B {\n    @Test func b() {}\n}"),
            (path: "C.swift", text: "@Suite(.bounded) enum C {\n    struct N {\n        @Test func c() {}\n    }\n}"),
            (path: "C+D.swift", text: "extension C.N {\n    @Test func d() {}\n}\n"),
            (path: "E.swift", text: "@Test(.bounded) func alone() {}\n")
        ])
        #expect(missing.isEmpty)
    }

    @Test func aTraitOfAnotherNameIsNotTheTrait() {
        let missing = BoundedSuites.missing(in: [
            (path: "A.swift", text: "@Suite(.boundedTwice)\nstruct ATests {\n    @Test func a() {}\n}\n")
        ])
        #expect(missing.map(\.name) == ["ATests"])
    }

    @Test func aBraceOrATestInACommentOrATextCountsForNothing() throws {
        let text = """
            struct Helper {
                // @Test func a() {
                /* @Test } /* nested } */ { */
                let one = "@Test }"
                let two = #"@Test \\(raw) "quoted" }"#
                let three = "\\(["@Test }": 1]["@Test }"] ?? 0) }"
                let four = \"""
                    @Test }
                    \"""
            }

            @Suite(.bounded)
            struct ATests {
                @Test func a() {}
            }
            """
        let missing = BoundedSuites.missing(in: [(path: "A.swift", text: text)])
        #expect(missing.isEmpty)
        let code = try #require(String(bytes: BoundedSuites.code(text), encoding: .utf8))
        #expect(code.components(separatedBy: "@Test").count == 2)
    }

    /// A test inside two suites with the trait takes one slot, not two: with every slot held by tests that wait for a
    /// second one, the run would never end.
    @Test func aTestInsideTwoSuitesWithTheTraitTakesOneSlot() async throws {
        let slots = BoundedSlots(count: 2)
        let trait = BoundedTrait(slots: slots)
        let test = try #require(Test.current)
        try await BoundedSlots.$isHeld.withValue(false) {
            try await trait.provideScope(for: test, testCase: nil) {
                #expect(await slots.free == 1)
                try await trait.provideScope(for: test, testCase: nil) {
                    #expect(await slots.free == 1)
                }
            }
        }
        #expect(await slots.free == 2)
    }
}
