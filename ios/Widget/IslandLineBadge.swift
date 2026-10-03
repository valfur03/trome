import TROMECore
import SwiftUI

struct IslandLineBadge: View {
    let line: TransitLine

    var body: some View {
        switch line.mode {
        case .metro:
            MetroLineBadge(line: line, size: .regular)
        case .rer:
            RERSquareBadge(line: line)
        }
    }
}
