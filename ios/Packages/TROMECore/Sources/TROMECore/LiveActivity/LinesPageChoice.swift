import Foundation

/// The line that the rider tapped to on the header of a Live Activity.
/// The server sends one content to every rider of a station, with the first page shown, so the choice lives on the
/// iPhone, in the storage that the app and the widget share, and the widget draws the chosen page from the pages
/// that each content carries. It holds for one Live Activity at one station: a new start shows the first page.
public struct LinesPageChoice: Codable, Hashable, Sendable {
    public var activityID: String
    public var stationName: String
    public var line: TransitLine

    public init(activityID: String, stationName: String, line: TransitLine) {
        self.activityID = activityID
        self.stationName = stationName
        self.line = line
    }
}

public struct LinesPageChoiceStore {
    static let key = "liveActivity.linesPageChoice"
    /// The Info.plist key of the app group that the app and the widget share; the build sets it in both.
    static let appGroupKey = "TROMEAppGroup"

    private let storage: any KeyValueStore

    public init(storage: any KeyValueStore) {
        self.storage = storage
    }

    /// The store that the app and its widget share, or nil when the build has no shared app group: the widget then
    /// draws the page of each content, as the app sends it.
    public static func ofThisApp(bundle: Bundle = .main) -> LinesPageChoiceStore? {
        guard let group = bundle.object(forInfoDictionaryKey: appGroupKey) as? String, !group.isEmpty,
              FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil,
              let defaults = UserDefaults(suiteName: group) else {
            return nil
        }
        return LinesPageChoiceStore(storage: defaults)
    }

    public func load() -> LinesPageChoice? {
        storage.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(LinesPageChoice.self, from: $0) }
    }

    func save(_ choice: LinesPageChoice) {
        storage.set(try? JSONEncoder().encode(choice), forKey: Self.key)
    }
}

extension StationActivityAttributes.ContentState {
    /// The content as the Live Activity `activityID` draws it: on the page of the line that its rider chose, when
    /// this content carries that page, with the minutes of this content; otherwise on the page that the content
    /// shows, which is the first page in a push of the server.
    public func showingThePage(chosenBy choice: LinesPageChoice?, activityID: String) -> Self {
        guard let page = trains.linesPage, let index = chosenIndex(by: choice, activityID: activityID),
              index != page.firstIndex, let chosen = page.showing(pageAt: index) else {
            return self
        }
        var state = self
        state.trains = .lines(chosen)
        return state
    }

    func chosenIndex(by choice: LinesPageChoice?, activityID: String?) -> Int? {
        guard let choice, choice.activityID == activityID, choice.stationName == stationName else { return nil }
        return trains.linesPage?.index(of: choice.line)
    }
}
