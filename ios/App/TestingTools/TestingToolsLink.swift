#if DEBUG
/// The link to the Testing tools, at the top right of the main screen of a debug build.
/// The store pictures launch the app with `--hide-testing-tools`, so that the screen shows what the store build shows.
enum TestingToolsLink {
    static let hideArgument = "--hide-testing-tools"

    static func isShown(launchArguments: [String]) -> Bool {
        !launchArguments.contains(hideArgument)
    }
}
#endif
