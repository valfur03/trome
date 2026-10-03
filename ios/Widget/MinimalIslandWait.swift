import TROMECore
import SwiftUI

struct MinimalIslandWait: View {
    let island: DynamicIslandWait
    let drawnAt: Date

    var body: some View {
        IslandNumber(value: island.minimalWait, drawnAt: drawnAt)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(island.spokenLineAndWait)
    }
}
