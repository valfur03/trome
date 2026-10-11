import TROMECore
import SwiftUI

extension DynamicIslandWait {
    var spokenWait: Text {
        switch wait {
        case .minutes(let train):
            Text(.currentDate, format: .offset(to: train.roundedUpCountdownEnd, allowedFields: [.minute], sign: .never))
        case .approaching:
            Text("Approaching")
        case .atPlatform:
            Text("At the platform")
        case .overAnHour:
            Text("Next train in over 1 hour")
        case .noTrain:
            Text("No trains")
        case .stale:
            .spokenOpenTheApp
        case .loading:
            Text("Loading the next trains…")
        case .noData, .timesUnavailable:
            .spokenTimesUnavailable
        case .updateTheApp:
            .spokenUpdateTheApp
        }
    }

    var spokenLineAndWait: Text {
        guard let line else { return spokenWait }
        return Text("\(Text(verbatim: line.localizedName)), \(spokenWait)")
    }
}
