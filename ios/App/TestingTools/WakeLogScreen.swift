#if DEBUG
import TROMECore
import SwiftUI

struct WakeLogScreen: View {
    @Environment(WakeLog.self) private var wakeLog: WakeLog?
    @Environment(LocationService.self) private var locationService
    @State private var phoneState: [String] = []

    var body: some View {
        List {
            Section("Phone now") {
                ForEach(phoneState, id: \.self) { line in
                    Text(line)
                }
            }
            Section("Newest first") {
                if entries.isEmpty {
                    Text("Nothing yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    WakeLogRow(entry: entry)
                }
            }
        }
        .navigationTitle("Wake log")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: shareText)
                    .disabled(entries.isEmpty)
                Button("Clear", systemImage: "trash", role: .destructive) {
                    wakeLog?.clear()
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

    private var shareText: String {
        (phoneState + [""] + entries.map { "\(WakeLogRow.time(of: $0)) [\($0.kind.rawValue)] \($0.text)" })
            .joined(separator: "\n")
    }
}

private struct WakeLogRow: View {
    let entry: WakeLogEntry

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text)
                Text(Self.time(of: entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(colour)
        }
    }

    static func time(of entry: WakeLogEntry) -> String {
        entry.date.formatted(.dateTime.day().month(.abbreviated).hour().minute().second())
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
