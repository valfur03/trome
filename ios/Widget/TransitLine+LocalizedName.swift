import Foundation
import TROMECore

extension TransitLine {
    var localizedName: String {
        switch mode {
        case .metro: String(localized: "Metro \(name)")
        case .rer: String(localized: "RER \(name)")
        }
    }
}
