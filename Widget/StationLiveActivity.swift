import ActivityKit
import RATPCore
import SwiftUI
import WidgetKit

struct StationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StationActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.stationName)
                    .font(.headline)
                Text(context.state.updatedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.stationName)
                        .font(.headline)
                }
            } compactLeading: {
                Image(systemName: "tram.fill")
            } compactTrailing: {
                Text(context.attributes.stationName)
                    .lineLimit(1)
            } minimal: {
                Image(systemName: "tram.fill")
            }
        }
    }
}

#Preview(
    "Lock screen",
    as: .content,
    using: StationActivityAttributes(stationName: "Châtelet")
) {
    StationLiveActivity()
} contentStates: {
    StationActivityAttributes.ContentState(updatedAt: .now)
}
