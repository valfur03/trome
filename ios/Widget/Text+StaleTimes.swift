import TROMECore
import SwiftUI

extension Text {
    static var timesUnavailable: Text {
        Text("Times unavailable")
    }

    static var spokenTimesUnavailable: Text {
        Text("Times unavailable for now")
    }

    static var spokenOpenTheApp: Text {
        Text("Open the app for new times.")
    }

    init(staleTimesOf state: StationActivityAttributes.ContentState) {
        self = state.serverIsOut ? .timesUnavailable : Text("Open the app")
    }

    init(spokenStaleTimesOf state: StationActivityAttributes.ContentState) {
        self = state.serverIsOut ? .spokenTimesUnavailable : .spokenOpenTheApp
    }
}
