import TROMECore
import SwiftUI

struct StationDataSourceNotice: View {
    @Environment(\.appName) private var appName
    @Environment(\.stationCatalog) private var stationCatalog

    var body: some View {
        if let dataDate = stationCatalog.dataDate {
            Text(
                AttributedString(
                    localized: """
                    Station list adapted by \(appName) from Île-de-France Mobilités data of \
                    \(dataDate, format: StationCatalog.dataDateStyle), under the \
                    [ODbL](https://opendatacommons.org/licenses/odbl/1-0/) and the \
                    [Licence Ouverte v2.0](https://www.data.gouv.fr/pages/legal/licences/etalab-2.0).
                    """
                )
                .underliningLinks()
            )
            .accessibilityIdentifier("stationDataSourceNotice")
        }
    }
}
