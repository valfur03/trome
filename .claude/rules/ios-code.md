---
paths:
  - "ios/App/**"
  - "ios/Widget/**"
  - "ios/Packages/**"
  - "ios/UITests/**"
  - "ios/RenderCheck/**"
  - "ios/DocsScreenshots/**"
  - "ios/project.yml"
  - "ios/Config/**"
---
# Code structure of the iOS app

These rules are for every change and every review of the iPhone app, its widget, its package and their tests.
decision-6 (section 10) explains these rules and their sources.
Follow them in every task.
The reviewer checks them: a file in the wrong place or a wrong dependency direction is a medium finding.

- **Two modules, one direction.** `ios/Packages/TROMECore` holds the rules, the state (`@Observable` models), the value types, the PRIM client, and the protocols of the system services.
  The app (`ios/App/`) and the widget (`ios/Widget/`) depend on `TROMECore`, never the reverse.
  The same package has one small SwiftUI module, `TROMEBadge`: the line badge that the app and the widget both draw, at the size of each surface; it depends on `TROMECore`, never the reverse.
  Why: when each surface drew its own badge, the digit was off the centre on some of them (TASK-335); one view, with a test that draws every badge on the Mac, keeps them all true.
- **`TROMECore` stays free of the UI and of iOS.** No `import SwiftUI`, `UIKit`, `WidgetKit` or `MapKit`.
  It must build and pass its tests on the Mac (`make test`).
  An iOS-only framework is allowed only for a type that the app and the widget share (today: the `ActivityAttributes` conformance and `SnoozeLiveActivityIntent`, the intent of the Live Activity's buttons), inside `#if os(iOS)`.
- **Views hold no rules.** A view reads a model and calls it.
  A rule goes in `TROMECore`, with unit tests.
- **Protocols in the core, adapters in the app.** For an Apple system service (ActivityKit, Core Location, notifications), `TROMECore` declares a small protocol, and the app implements it in a file named after the framework (`ActivityKitStationLiveActivityClient`, `CoreLocationProvider`, `UserNotificationArrivalNotifier`).
  Unit tests use fakes.
  Foundation types that run on the Mac (`URLSession`, `UserDefaults`) may conform inside `TROMECore`.
- **One composition root.** `ios/App/TROMEApp.swift` makes the models and the adapters and gives them to the views.
  No singleton that the app defines, no global state.
- **Folders by feature, with the same names everywhere.** `ios/App/`, `ios/Packages/TROMECore/Sources/TROMECore/` and `ios/Packages/TROMECore/Tests/TROMECoreTests/` use the same feature folders: `Stations`, `Location`, `Trains`, `LiveActivity`, `AutoLiveActivity`, `Example`, `About`.
  The app also has `AppName`, `Permissions`, `NightLook` (the look of the main screen: its palette, its cards, pills and buttons) and `TestingTools`, and the package has `Logging` (the one name of the log, `Logger.subsystem`).
  New code goes in the folder of its feature.
  A new feature gets a new folder in each module where it has code.
  No layer folders (`Views/`, `Models/`, `Services/`, `Helpers/`), and no loose files at the top of a module.
  The only exceptions: `TROMEApp.swift` and `ContentView.swift` (the main screen) at the top of `ios/App/`, the String Catalogs (`Localizable.xcstrings`, `InfoPlist.xcstrings`) at the top of `ios/App/` and `ios/Widget/`,
  the privacy manifest (`PrivacyInfo.xcprivacy`, the name that Apple requires) at the top of `ios/App/`, and of `ios/Widget/` once the code of the widget uses an API that needs a reason, the asset catalog of the app icon (`Assets.xcassets`, where Xcode looks for it) at the top of `ios/App/`, and `Resources/` in the package.
- **Testing tools are for debug builds only.** Each file in `ios/App/TestingTools/` is inside `#if DEBUG`.
- **The widget is a pure view.** `ios/Widget/` uses only `StationActivityAttributes` and its value types from `TROMECore`, and `SnoozeLiveActivityIntent` for its buttons (iOS runs the intent in the app, not in the widget).
  No model, no provider, no network.
  It also uses `TROMEBadge` for the line badges.
  The app compiles `Widget/LineBadge.swift` (the badge with the name that VoiceOver reads) and `Widget/TransitLine+LocalizedName.swift`, listed one by one in the sources of the app in `ios/project.yml`, so that the main screen and the Live Activity draw the same badges.
  Such a shared file stays a pure view, with the texts of both String Catalogs.
- **Texts in French and English.** Each text that a user sees is written in English in the code, and has its French text in the String Catalog of its target, in the same task (`ios/guide/languages.md`).
  `make check` fails on a text with no French text (`make strings-check`).
  A French text that holds a station name puts the name first, as a label, never after `de` or `à`, and you check it in French at Abbesses or Le Kremlin-Bicêtre, not only at Châtelet (`ios/guide/languages.md`, "Write French that a Paris rider would say").
  Use a text that SwiftUI translates (`Text("...")`, a `LocalizedStringKey`) or `String(localized:)`, never a plain `String` given to `Text`.
  The texts of `ios/App/TestingTools/` stay in English: they are inside `#if DEBUG`, so Xcode keeps them out of the catalog.
  The catalogs in git must be the ones that Xcode writes, so that a build in Xcode in the main folder changes no file: after you change a text, run `make strings-sync`, then add the French texts and commit the catalogs (`make strings-check` fails when a build in Xcode would change a catalog).
  The texts of `TROMECore` (for example `TransitLine.displayName`) are not translated: the app and the widget make the texts that a user sees.
  The name of the app is written once, `APP_NAME` in `ios/Config/Base.xcconfig` (decision-43): never write it in a text of the app or the widget.
  A view reads it with `@Environment(\.appName)` and puts it in its text as an argument (`%@` in the catalog); a permission text of `ios/project.yml` uses `$(APP_NAME)`, and `make strings-sync` puts it in their French texts.
- **A text on a screen has a job.** It names an action, says a state, or meets a legal duty (a licence notice).
  A sentence that explains or reassures goes to the Help page or the docs, and the screen shows the state with an icon, a colour and a position (a pill, an orange card, a dimmed row).
  A text that must stay gets the fewest words that work, on one line when it can; VoiceOver still gets a label for each state.
  Why: a rider scans the screen and does not read it, and the Help page can say it once, with room (the prompter's order of 2026-10-07, TASK-298).
  The reviewer checks each new text against this rule.
- **Access control.** In `TROMECore`, only what the app or the widget uses is `public`.
  The rest stays `internal`.
  Tests use `@testable import TROMECore`.
- **Files.** A file holds one main type and has its name.
  Small types that exist only for it (its state, its error, the protocol of its dependency) may stay in the same file.
  An extension that adds a topic goes in `Type+Topic.swift`.
  Names say the role: `...View`, `...Section`, `...Screen`, `...Model`, `...Rules`, `...Store`, and the framework name first for an adapter.
- **Tests.** Unit tests: `ios/Packages/TROMECore/Tests/TROMECoreTests/<Feature>/<Type>Tests.swift`.
  The test of the line badge draws every badge on the Mac: `ios/Packages/TROMECore/Tests/TROMEBadgeTests/LineBadge/`.
  The recorded PRIM answers are in `contracts/prim/`, shared with the server tests (`Fixture.data(_:)` reads them).
  E2E tests: `ios/UITests/`, one file per seam with iOS (see `.claude/rules/tests.md`).
  Tests of the scripts: `ios/scripts/tests/<name>-test.sh` (`make test-scripts`, with a fake `xcrun` for the Simulator scripts).
  Docs screenshots: `ios/DocsScreenshots/`.
  The render check of the Live Activity views: `ios/RenderCheck/`.
  Code that needs a unit test goes in `TROMECore`.
- **No warnings.** `make check` fails on any build warning and when a newer Xcode may recommend new project settings (`ios/README.md`, section "Before you commit"; `make recommended-settings-check` prints the steps for new settings).
  Fix the cause.
  Never silence a warning, and never raise `options.xcodeVersion` in `ios/project.yml` without adding the settings that Xcode proposes.
  An agent cannot open that Xcode dialog: when `make recommended-settings-check` fails, ask the prompter (label `needs-prompter`).
- **New module.** Add a target in `ios/Packages/` only when it solves a real problem (code that must not see the rest, code shared with a new target, build time).
  Deeper changes that these rules call for are `tech` tasks.
- **The note for riders.** A change of the app code that a rider or a builder will notice adds its note in `ios/changes/` (format and kinds: `ios/changes/README.md`); a change that nobody will notice says so in a commit, most often a title that ends with "(no rider change)" (the other ways: the same file).
  `make check` fails on a change of the app code with neither, but it cannot judge which one is true.
  The reviewer reads the note, or the marker, against the diff: a change that a rider will notice with a "(no rider change)" marker, or a note with a wrong kind or a false line, is a medium finding.
  The reviewer confirms a headline, never its author alone (`.claude/rules/writing.md`, row "The notes of a version").
