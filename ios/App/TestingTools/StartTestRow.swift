#if WAKE_LOG
import Foundation
import SwiftUI
import TROMECore

/// The test of the start, in the Wake log: one tap asks the server, as a wake at a station does, to start the Live
/// Activity of the nearest station (`AutoLiveActivityModel.testTheStart`), so that a build for a walk proves the push at
/// a desk. The row says only whether the ask left: the answer is in the lines of the log, as for a wake.
/// One tap per opening of the screen, so a slip never asks twice.
/// Its texts are verbatim, as every text of the Wake log, but in the language of the app: a Release build must add
/// nothing to the String Catalogs, and the build for a walk is read on a French phone.
struct StartTestRow: View {
    @Environment(AutoLiveActivityModel.self) private var autoLiveActivity
    @State private var asked: Bool?

    var body: some View {
        // One button whatever the state: a row that swaps its view in a List kept the height of the old one.
        Button {
            guard asked == nil else { return }
            asked = autoLiveActivity.testTheStart()
        } label: {
            HStack {
                title
                Spacer()
                if let asked {
                    status(asked)
                }
            }
        }
        .accessibilityIdentifier("testTheStart")
    }

    /// "Sent" with its icon; a red cross alone when nothing left, as the log under it says why.
    private func status(_ asked: Bool) -> some View {
        Label {
            Text(verbatim: asked ? text("Sent", "Envoyé") : text("Not sent", "Non envoyé"))
        } icon: {
            Image(systemName: asked ? "paperplane.fill" : "xmark.circle")
                .foregroundStyle(asked ? Color.accentColor : .red)
        }
        .labelStyle(StatusLabelStyle(showsTitle: asked))
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("testTheStartStatus")
    }

    private var title: some View {
        Label {
            Text(verbatim: text("Test the start", "Tester le démarrage"))
        } icon: {
            Image(systemName: "dot.radiowaves.up.forward")
        }
    }

    private func text(_ english: String, _ french: String) -> String {
        Bundle.main.preferredLocalizations.first == "fr" ? french : english
    }
}

/// The icon and the title, or the icon alone, which VoiceOver still reads with its title.
private struct StatusLabelStyle: LabelStyle {
    let showsTitle: Bool

    func makeBody(configuration: Configuration) -> some View {
        if showsTitle {
            Label(configuration)
        } else {
            Label(configuration).labelStyle(.iconOnly)
        }
    }
}
#endif
