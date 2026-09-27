import Foundation
import RATPCore

extension TransitLine {
    var localizedName: String {
        switch mode {
        case .metro: String(localized: "Metro \(name)")
        case .rer: String(localized: "RER \(name)")
        }
    }
}
