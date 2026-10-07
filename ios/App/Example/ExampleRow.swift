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
        NightCard {
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
                            .font(.headline)
                            .foregroundStyle(isDisabled ? NightLook.secondaryText : NightLook.text)
                        explanation
                            .font(.footnote)
                            .foregroundStyle(NightLook.secondaryText)
                            .accessibilityIdentifier("exampleExplanation")
                    }
                } icon: {
                    IconChip(systemImage: "eye.fill")
                        .opacity(isDisabled ? 0.5 : 1)
                }
                .labelStyle(.rowTitle)
                .frame(maxWidth: .infinity, minHeight: NightLook.minimumTapHeight, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .accessibilityIdentifier("seeAnExample")
        }
    }

    private var isDisabled: Bool {
        realTrainsStation != nil
    }

    private var explanation: Text {
        if let station = realTrainsStation {
            return Text("\(station.name): the real trains are already on the lock screen.")
        }
        let name = autoLiveActivity.exampleStation?.name ?? ""
        let minutes = Int(AutoLiveActivityRules.defaultExampleDuration / 60)
        return Text("\(name) on the lock screen, with sample times, for \(minutes) minutes.")
    }
}
