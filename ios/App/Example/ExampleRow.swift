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
                        if isDisabled {
                            Text("Real trains already showing")
                                .font(.footnote)
                                .foregroundStyle(NightLook.secondaryText)
                                .accessibilityIdentifier("exampleExplanation")
                        }
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
}
