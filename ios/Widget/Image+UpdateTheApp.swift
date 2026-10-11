import SwiftUI

/// The look of the state where the server refused the app token: only an update of the app brings the times back.
extension Image {
    static var updateTheApp: Image {
        Image(systemName: "arrow.down.app.fill")
    }
}

extension Color {
    static var updateTheApp: Color {
        .orange
    }
}
