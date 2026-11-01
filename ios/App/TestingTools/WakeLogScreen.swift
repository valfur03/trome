#if WAKE_LOG
import TROMECore
import SwiftUI

/// The Wake log: what iOS woke the app for and what the app decided, newest first, with the settings that can stop
/// a wake. A debug build opens it from the Testing tools, and a build for a walk from the main screen.
/// Its texts are verbatim, in English: a Release build for a walk must add nothing to the String Catalogs.
struct WakeLogScreen: View {
    @Environment(WakeLog.self) private var wakeLog: WakeLog?
    @Environment(LocationService.self) private var locationService
    @State private var phoneState: [String] = []

    var body: some View {
        List {
            Section {
                ForEach(phoneState, id: \.self) { line in
                    Text(line)
                }
            } header: {
                Text(verbatim: "Phone now")
            }
            Section {
                if entries.isEmpty {
                    Text(verbatim: "Nothing yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    WakeLogRow(entry: entry)
                }
            } header: {
                Text(verbatim: "Newest first")
            }
        }
        .navigationTitle(Text(verbatim: "Wake log"))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: wakeLog?.report(phone: phoneState) ?? "")
                    .disabled(entries.isEmpty)
                Button(role: .destructive) {
                    wakeLog?.clear()
                } label: {
                    Label { Text(verbatim: "Clear") } icon: { Image(systemName: "trash") }
                }
                .disabled(entries.isEmpty)
            }
        }
        .task {
            phoneState = await PhoneStateReport.lines(locationSource: locationService.source)
        }
    }

    private var entries: [WakeLogEntry] {
        wakeLog?.entries ?? []
    }
}

private struct WakeLogRow: View {
    let entry: WakeLogEntry

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text)
                Text(WakeLog.time(of: entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(colour)
        }
    }

    private var icon: String {
        switch entry.kind {
        case .launch: "power"
        case .system: "location.circle"
        case .regions: "map"
        case .decision: "arrow.triangle.branch"
        case .notification: "bell"
        case .silentStart: "dot.radiowaves.up.forward"
        case .trains: "tram"
        }
    }

    private var colour: Color {
        switch entry.kind {
        case .launch: .secondary
        case .system: .blue
        case .regions: .teal
        case .decision: .orange
        case .notification: .green
        case .silentStart: .purple
        case .trains: .indigo
        }
    }
}
#endif
