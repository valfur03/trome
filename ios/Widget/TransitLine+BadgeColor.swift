import TROMECore
import SwiftUI

extension TransitLine {
    var badgeColor: Color {
        color?.backgroundRGB.map(Color.init(lineRGB:)) ?? .gray
    }

    var badgeTextColor: Color {
        color?.textRGB.map(Color.init(lineRGB:)) ?? .primary
    }
}

private extension Color {
    init(lineRGB rgb: LineColor.RGB) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
