import SwiftUI
import TROMEBadge
import TROMECore

/// The badge of a line, as every surface of the Live Activity and the app draws it, with the name that VoiceOver
/// reads. The app compiles this file too, so that both draw the same badge.
struct LineBadge: View {
    let line: TransitLine
    let surface: LineBadgeSurface

    var body: some View {
        LineBadgeView(line: line, surface: surface)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line.localizedName)
    }
}
