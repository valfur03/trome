import TROMEBadge
import TROMECore
import SwiftUI

struct SielPlate<Content: View>: View {
    let line: TransitLine
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(line.badgeColor)
                .frame(width: 5)
            VStack(spacing: 0) {
                content
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
