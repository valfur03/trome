import AppIntents
import RATPCore
import SwiftUI

struct SnoozeButtons: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(showsTitle: true)
            row(showsTitle: false)
        }
    }

    private func row(showsTitle: Bool) -> some View {
        HStack(spacing: 6) {
            Label("Snooze", systemImage: "bell.slash")
                .labelStyle(SnoozeLabelStyle(showsTitle: showsTitle))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            ForEach(SnoozeDuration.allCases, id: \.self) { duration in
                Button(intent: SnoozeLiveActivityIntent(duration: duration)) {
                    Text(title(of: duration))
                        .font(.caption2.bold())
                        .lineLimit(1)
                        .fixedSize()
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.mini)
                .accessibilityLabel(accessibilityTitle(of: duration))
            }
        }
    }

    private func title(of duration: SnoozeDuration) -> LocalizedStringKey {
        switch duration {
        case .thirtyMinutes: "30 min"
        case .oneHour: "1 h"
        case .restOfToday: "Today"
        }
    }

    private func accessibilityTitle(of duration: SnoozeDuration) -> LocalizedStringKey {
        switch duration {
        case .thirtyMinutes: "Snooze for 30 minutes"
        case .oneHour: "Snooze for 1 hour"
        case .restOfToday: "Snooze for the rest of today"
        }
    }
}

private struct SnoozeLabelStyle: LabelStyle {
    let showsTitle: Bool

    func makeBody(configuration: Configuration) -> some View {
        if showsTitle {
            Label(configuration)
        } else {
            configuration.icon
        }
    }
}
