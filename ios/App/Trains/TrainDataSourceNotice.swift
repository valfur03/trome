import SwiftUI

struct TrainDataSourceNotice: View {
    var body: some View {
        Text(
            AttributedString(
                localized: """
                Train times: ‘[Prochains passages](https://prim.iledefrance-mobilites.fr)’ \
                of Île-de-France Mobilités (PRIM), under the \
                ‘[Licence Mobilités](https://prim.iledefrance-mobilites.fr/en/licences)’.
                """
            )
            .underliningLinks()
        )
        .accessibilityIdentifier("trainDataSourceNotice")
    }
}
