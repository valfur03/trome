# Add or change a text in English and French

Most riders of TROME are French, so every text that a rider sees has a French version, and `make check` fails on a text without one.
This page shows how to add or change a text, where its French text goes, and what to do when that check, `make strings-check`, fails.
Run the commands from the root of the repo; the paths on this page start there too.

## Add or change a text

You write each text in English in the Swift code, and its French text in a String Catalog, a `.xcstrings` file ([which catalog](#which-catalog-holds-a-text)).
The English text is the key of its entry in the catalog.

1. Write the English text in the code, in a form that SwiftUI translates:
   - `Text("...")`, `Button("...")`, or any other view that takes a `LocalizedStringKey`;
   - `String(localized: "...")` when you need a `String`, for example for a notification.

   A `String` variable given to `Text` shows as it is, with no translation.
   For a text that is never translated, such as the name of a station, use `Text(verbatim:)`.
2. Bring the change into the String Catalogs:

   ```sh
   make strings-sync
   ```

   It updates the catalogs as a build in Xcode does, so it takes about as long as a build.
   It adds each new text with no French text, and marks a text that is no longer in the code as **stale**.
   When you change an English text, the catalog then holds a new entry with no French text, and the old entry, stale, with the old French text.
3. Write the French text of each new entry, and mark it **translated**.
   In Xcode, open the catalog, choose French, and type the text: Xcode marks it **translated**.
   In the JSON, give the entry a `"fr"` localization with the state `"translated"`:

   ```json
   "No trains" : {
     "localizations" : {
       "fr" : {
         "stringUnit" : {
           "state" : "translated",
           "value" : "Pas de train"
         }
       }
     }
   },
   ```

   Then run `make strings-sync` again, so that the file is written the way Xcode writes it.
4. Delete the stale entries.
5. Check the change with `git diff`, run `make strings-check`, and commit the catalogs with your code.

## See your text in French

The app shows its texts in French when the language of the iPhone is French, and in English for any other language (**Settings > General > Language & Region**).
To see the whole Simulator in French, run `make run LANGUAGE=fr`, or `make switch-language LANGUAGE=fr` when the app already runs (it keeps the data of the app).

## Which catalog holds a text

| Catalog | Its texts |
|---|---|
| `ios/App/Localizable.xcstrings` | The main screen and the notifications |
| `ios/App/InfoPlist.xcstrings` | The texts that iOS shows for the app: the name under the icon, and why the app asks for the location |
| `ios/Widget/Localizable.xcstrings` | The Live Activity and the Dynamic Island |

The permission texts are written in English in `ios/project.yml`, not in the code; `make strings-sync` brings them into `ios/App/InfoPlist.xcstrings`.

## Write French that a Paris rider would say

Write the French text that a rider reads on the signs of the RATP and in iOS, not a word-for-word translation: **Prochains passages**, **écran verrouillé**, **activité en direct**, **Réglages**, **Toujours**.
The [table of terms](../../docs/README.md#write-the-riders-pages-in-french) of the docs gives the words that the app already uses.

## Texts with no French text

- **The Testing tools.** Their texts stay in English: they are inside `#if DEBUG`, so Xcode leaves them out of the catalog.
- **The texts of `TROMECore`**, such as the name of a line (`TransitLine.displayName`): the app and the Live Activity build the texts that a rider reads, and translate those.
- **The name of the app**, which is the same in French: it is marked **Don't translate** in the catalog, and needs no French text.

## The name of the app

The name of the app, TROME, is written once: `APP_NAME` in `ios/Config/Base.xcconfig`.
Never write it in a text of the app or of the Live Activity:

- a view reads it with `@Environment(\.appName)` and puts it in its text, which the catalog shows as `%@`;
- a permission text of `ios/project.yml` writes `$(APP_NAME)`, and `make strings-sync` puts the name in its French text.

To rename the app, change that line, and run `make strings-sync`.

## When make strings-check fails

`make strings-check` is part of `make check`, and needs no Simulator.
Its message says what is wrong:

| It says | Do this |
|---|---|
| `a build in Xcode would change: ...`, with a diff | Run `make strings-sync`, then write the French texts of the new texts. |
| `no fr text marked "translated" for "..."` | Write the French text, and mark it **translated**. Xcode marks a French text **Needs Review** when its English text changed: check it, then mark it **translated**. |
| `"..." is no longer in the code; remove it` | Delete the entry from the catalog. |
| `app-name-sync: ... does not say ...` | A French permission text lost the name of the app, for example after a build in Xcode: write the name in it. |

The check is strict for one reason: the catalogs in git must be exactly the ones that Xcode writes.
Then a build in Xcode on `main` changes no file, and `git status` stays clean.
The command line builds (`make build`, `make run`, `make check`, `make e2e`) never change the catalogs; only a build in Xcode and `make strings-sync` do.
