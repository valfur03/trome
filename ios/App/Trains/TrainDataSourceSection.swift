import SwiftUI

struct TrainDataSourceSection: View {
    var body: some View {
        Section {
            Text(
                """
                Contains information from the ‘[Prochains passages](https://prim.iledefrance-mobilites.fr)’ \
                database of Île-de-France Mobilités (PRIM), made available under the \
                ‘[Licence Mobilités](https://prim.iledefrance-mobilites.fr/en/licences)’.
                """
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("trainDataSourceNotice")
            .listRowBackground(Color.clear)
        }
    }
}
