import Foundation
import Testing
@testable import TROMECore

/// The record of a walk says which build was walked and on which iOS, with no question to the rider.
@Suite(.bounded)
struct AppBuildTests {
    @Test func namesTheBuildItsCommitAndIOS() {
        let build = AppBuild(infoDictionary: ["CFBundleVersion": "6", AppBuild.commitKey: "1e2e704"])

        #expect(build.summary(iOSVersion: "26.1") == "build 6, commit 1e2e704, iOS 26.1")
    }

    @Test func saysWhenTheBuildHadChangesNotCommitted() {
        let build = AppBuild(infoDictionary: ["CFBundleVersion": "6", AppBuild.commitKey: "1e2e704-dirty"])

        #expect(build.summary(iOSVersion: "26.1") == "build 6, commit 1e2e704 with changes not committed, iOS 26.1")
    }

    @Test func saysUnknownWhenTheBuildNamesNoCommit() {
        for written: Any? in [nil, "", "$(TROME_COMMIT)", "-dirty", "1E2E704", "1e2e70", 1_234_567] {
            let build = AppBuild(infoDictionary: ["CFBundleVersion": "6", AppBuild.commitKey: written as Any])

            #expect(build.summary(iOSVersion: "26.1") == "build 6, commit unknown, iOS 26.1")
        }
    }

    /// The record holds no key and no token: the launch line reads only the build number and the commit, and a
    /// commit that is no hash is never written as it is.
    @Test func writesNoOtherValueOfTheInfoPlist() {
        let build = AppBuild(infoDictionary: [
            "CFBundleVersion": "6",
            AppBuild.commitKey: "KEY-0123abcd",
            "PRIMAPIKey": "KEY-0123abcd",
            "TrainServerAppToken": "TOKEN-4567",
            "TrainServerHost": "trains.example.com"
        ])

        let summary = build.summary(iOSVersion: "26.1")

        #expect(summary == "build 6, commit unknown, iOS 26.1")
        #expect(!["KEY-0123abcd", "TOKEN-4567", "trains.example.com"].contains { summary.contains($0) })
    }
}
