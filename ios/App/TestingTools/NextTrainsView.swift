#if DEBUG
import RATPCore
import SwiftUI

struct NextTrainsView: View {
    let state: NextTrainsState

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView("Loading the next trains…")
                .accessibilityIdentifier("nextTrainsLoading")
        case .missingKey:
            message(
                "Live train times are not available: the train data key is not set.",
                identifier: "missingKeyMessage"
            )
        case .departures(let board, let updatedAt):
            DepartureBoardView(board: board, updatedAt: updatedAt)
        case .noLiveData:
            message("No live data for this station right now.", identifier: "noLiveDataMessage")
        case .failed(let error):
            failure(error)
        }
    }

    @ViewBuilder
    private func failure(_ error: NextTrainsError) -> some View {
        switch error {
        case .unreachable:
            message(
                "The app cannot reach the train data service. Check your internet connection.",
                identifier: "serviceUnreachableMessage"
            )
        case .keyRejected:
            message(
                "The train data service refused the key. Check the train data key.",
                identifier: "keyRejectedMessage"
            )
        case .quotaExceeded:
            message(
                "The train data service received too many requests today. Try again later.",
                identifier: "quotaExceededMessage"
            )
        case .serviceFailure:
            message(
                "The train data service does not work right now. The app will try again.",
                identifier: "serviceFailureMessage"
            )
        }
    }

    private func message(_ text: String, identifier: String) -> some View {
        Text(text)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier(identifier)
    }
}

private struct DepartureBoardView: View {
    static let clockTick: TimeInterval = 10

    let board: DepartureBoard
    let updatedAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.clockTick)) { context in
            let groups = board.groups
                .map { ($0, $0.upcomingTimes(after: context.date)) }
                .filter { !$0.1.isEmpty }
            VStack(spacing: 8) {
                if groups.isEmpty {
                    ProgressView("Updating the next trains…")
                        .accessibilityIdentifier("nextTrainsLoading")
                }
                ForEach(groups, id: \.0.id) { group, times in
                    DepartureRow(group: group, times: times, now: context.date)
                }
                Text("Updated at \(updatedAt.formatted(date: .omitted, time: .standard))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("nextTrainsUpdatedAt")
            }
        }
    }
}

private struct DepartureRow: View {
    let group: DepartureGroup
    let times: [Date]
    let now: Date

    private var timesText: String {
        times
            .map { time in
                let minutes = DepartureTime.minutes(until: time, from: now)
                return minutes == 0 ? "Now" : "\(minutes) min"
            }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(group.line.displayName)
                .font(.subheadline.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
            Text(group.destination)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(timesText)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("departureRow")
    }
}
#endif
