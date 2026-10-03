#if DEBUG
import TROMECore
import SwiftUI

struct NextTrainsScreen: View {
    let primConfiguration: PRIMConfiguration?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                NextTrainsSection()
                Text(primConfiguration == nil ? "Train data key: not set" : "Train data key: set")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("primKeyStatus")
            }
            .padding()
        }
        .navigationTitle("Next trains")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
