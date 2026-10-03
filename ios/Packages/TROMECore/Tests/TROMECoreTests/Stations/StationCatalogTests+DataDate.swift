import Foundation
import Testing
@testable import TROMECore

struct StationCatalogDataDateTests {
    @Test(arguments: [
        ("fr_FR", "27 septembre 2026"),
        ("en_GB", "27 September 2026"),
        ("en_US", "September 27, 2026")
    ])
    func showsTheDateOfTheDataInTheLanguageOfThePhone(locale: String, expected: String) throws {
        let catalog = try StationCatalog(jsonData: Data(#"{"date": "2026-09-27", "stations": []}"#.utf8))
        let date = try #require(catalog.dataDate)

        #expect(StationCatalog.dataDateStyle.locale(Locale(identifier: locale)).format(date) == expected)
    }

    @Test(arguments: [
        #"{"stations": []}"#,
        #"{"date": "27/09/2026", "stations": []}"#,
        #"[]"#
    ])
    func rejectsAFileWithNoDateOfTheData(json: String) {
        #expect(throws: (any Error).self) { try StationCatalog(jsonData: Data(json.utf8)) }
    }

    @Test func noticeGivesTheDateOfTheBundledData() throws {
        let date = try #require(try StationCatalog.bundled().dataDate)
        let isoDate = Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day().format(date)
        let appDate = StationCatalog.dataDateStyle.locale(Locale(identifier: "en_US")).format(date)

        let notice = try String(contentsOf: Self.noticeFile(), encoding: .utf8)

        #expect(notice.contains("The data of `stations.json` dates from \(isoDate),"))
        #expect(notice.contains("the date of the last update of the data, as the Licence Ouverte asks: \(isoDate)."))
        #expect(notice.contains("Île-de-France Mobilités data of \(appDate), under"))
    }

    private static func noticeFile(from file: String = #filePath) throws -> URL {
        var folder = URL(filePath: file).deletingLastPathComponent()
        while folder.pathComponents.count > 1 {
            let candidate = folder.appending(path: "NOTICE.md")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            folder = folder.deletingLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
