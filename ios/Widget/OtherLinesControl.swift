import SwiftUI

struct OtherLinesControl: View {
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            Text(verbatim: "+\(count)")
            Image(systemName: "chevron.right")
                .font(.caption.bold())
        }
        .font(.subheadline.bold())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
        .accessibilityHidden(true)
    }
}
