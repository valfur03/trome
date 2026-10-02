import SwiftUI

struct StationDataSourceNotice: View {
    @Environment(\.appName) private var appName

    var body: some View {
        Text(
            """
            Station list adapted by \(appName) from Île-de-France Mobilités data, under the \
            [ODbL](https://opendatacommons.org/licenses/odbl/1-0/) and the \
            [Licence Ouverte v2.0](https://www.data.gouv.fr/pages/legal/licences/etalab-2.0).
            """
        )
        .accessibilityIdentifier("stationDataSourceNotice")
    }
}
