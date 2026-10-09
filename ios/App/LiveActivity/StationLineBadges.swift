import TROMECore
import SwiftUI

struct StationLineBadges: View {
    let lines: [TransitLine]

    var body: some View {
        WrappingLayout(spacing: 6) {
            ForEach(lines, id: \.self) { line in
                LineBadge(line: line, surface: .header)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WrappingLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(of: subviews, in: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var top = bounds.minY
        for row in rows(of: subviews, in: bounds.width) {
            var leading = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: leading, y: top), proposal: ProposedViewSize(size))
                leading += size.width + spacing
            }
            top += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(of subviews: Subviews, in maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let widthWithIt = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, widthWithIt > maxWidth {
                rows.append(row)
                row = Row(indices: [index], width: size.width, height: size.height)
            } else {
                row.indices.append(index)
                row.width = widthWithIt
                row.height = max(row.height, size.height)
            }
        }
        if !row.indices.isEmpty {
            rows.append(row)
        }
        return rows
    }
}
