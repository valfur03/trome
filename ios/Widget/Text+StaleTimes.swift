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

    /// The server refused the app token of this build: the icon and its colour say it first, the words name
    /// the action.
    static var updateTheApp: Text {
        Text("\(Text(Image.updateTheApp).foregroundStyle(Color.updateTheApp)) Update the app")
    }

    static var spokenUpdateTheApp: Text {
        Text("Update the app to get the times.")
    }

    init(staleTimesOf state: StationActivityAttributes.ContentState) {
        if state.appNeedsUpdate {
            self = .updateTheApp
        } else {
            self = state.serverIsOut ? .timesUnavailable : Text("Open the app")
        }
    }

    init(spokenStaleTimesOf state: StationActivityAttributes.ContentState) {
        if state.appNeedsUpdate {
            self = .spokenUpdateTheApp
        } else {
            self = state.serverIsOut ? .spokenTimesUnavailable : .spokenOpenTheApp
        }
    }
}
