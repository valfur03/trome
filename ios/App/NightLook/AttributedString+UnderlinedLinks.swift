import SwiftUI

extension AttributedString {
    func underliningLinks() -> AttributedString {
        var underlined = self
        for run in underlined.runs where run.link != nil {
            underlined[run.range].underlineStyle = .single
        }
        return underlined
    }
}
