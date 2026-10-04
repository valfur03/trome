import TROMECore
import SwiftUI

extension Text {
    static var timesUnavailable: Text {
        Text("Times unavailable for now")
    }

    init(staleTimesOf state: StationActivityAttributes.ContentState) {
        self = state.serverIsOut ? .timesUnavailable : Text("Open the app for new times.")
    }

    init(noDataOf state: StationActivityAttributes.ContentState) {
        self = state.serverIsOut ? .timesUnavailable : Text("No data available")
    }
}
