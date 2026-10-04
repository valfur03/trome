import TROMECore
import SwiftUI

struct ExampleRow: View {
    @Environment(StationLiveActivityModel.self) private var liveActivity
    @Environment(AutoLiveActivityModel.self) private var autoLiveActivity
    @State private var isStarting = false

    private var realTrainsStation: Station? {
        liveActivity.isShowing ? autoLiveActivity.shownStation : nil
    }

    var body: some View {
        Button {
            guard !isStarting else { return }
            isStarting = true
            Task {
                await autoLiveActivity.exampleTapped()
                isStarting = false
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("See an example")
                    explanation
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("exampleExplanation")
                }
            } icon: {
                Image(systemName: "eye")
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(.rect)
        }
        .disabled(realTrainsStation != nil)
        .accessibilityIdentifier("seeAnExample")
    }

    private var explanation: Text {
        if let station = realTrainsStation {
            return Text("The real trains of \(station.name) are already on the lock screen.")
        }
        let minutes = Int(AutoLiveActivityRules.defaultExampleDuration / 60)
        return Text("\(autoLiveActivity.exampleStation?.name ?? "") on the lock screen, with sample times, for \(minutes) minutes.")
    }
}
