import SwiftUI

struct TrainDataSourceNotice: View {
    var body: some View {
        Text(
            """
            Contains information from the ‘[Prochains passages](https://prim.iledefrance-mobilites.fr)’ \
            database of Île-de-France Mobilités (PRIM), made available under the \
            ‘[Licence Mobilités](https://prim.iledefrance-mobilites.fr/en/licences)’.
            """
        )
        .accessibilityIdentifier("trainDataSourceNotice")
    }
}
