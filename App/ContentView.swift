import RATPCore
import SwiftUI

struct ContentView: View {
    private let primConfiguration = PRIMConfiguration(infoDictionary: Bundle.main.infoDictionary)

    var body: some View {
        VStack(spacing: 12) {
            Text("RATP Activity")
                .font(.largeTitle.bold())
                .accessibilityIdentifier("appTitle")
            Text(primConfiguration == nil ? "Train data key: not set" : "Train data key: set")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("primKeyStatus")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
