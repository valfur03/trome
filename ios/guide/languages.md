# Add or change a text in English and French

Most riders of the Paris metro read French, so every text that a rider sees has a French version, and `make check` fails on a text without one.
You write the English text in the Swift code, and its French text in a String Catalog, a `.xcstrings` file.
Run the commands from the root of the repo.

## Add or change a text

1. Write the English text in the code, in a form that SwiftUI translates: `Text("...")`, `Button("...")` or another view that takes a `LocalizedStringKey`, or `String(localized: "...")` when you need a `String`.
   A `String` variable given to `Text` is never translated; for a text that must stay as it is, such as a station name, use `Text(verbatim:)`.
2. Run `make strings-sync`.
   It updates the catalogs as a build in Xcode does, and takes about as long.
   The English text is the key of an entry, so a changed text gets a new entry with no French text, and its old entry is marked **stale**.
3. Write the French text of each new entry, and mark it **translated**.
   In Xcode, open the catalog, choose French, and type the text.
   In the JSON, give the entry a `"fr"` localization:

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
4. Delete the stale entries, run `make strings-check`, and commit the catalogs with your code.

To see the whole Simulator in French, run `make run LANGUAGE=fr`, or `make switch-language LANGUAGE=fr` when the app already runs (it keeps the data of the app).

## Which catalog holds a text

| Catalog | Its texts |
|---|---|
| `ios/App/Localizable.xcstrings` | The screens of the app and the notifications |
| `ios/App/InfoPlist.xcstrings` | The name under the icon, and the permission texts, which are written in English in `ios/project.yml` |
| `ios/Widget/Localizable.xcstrings` | The Live Activity and the Dynamic Island |

## Write French that a Paris rider would say

Use the words of the RATP signs and of iOS in French, not a word-for-word translation: **Prochains passages**, **écran verrouillé**, **activité en direct**, **Réglages**.
The [table of terms](../../docs/README.md#write-the-riders-pages-in-french) gives the words that the app already uses.

Some texts have no French text: the Testing tools, which are inside `#if DEBUG`, the texts of `TROMECore`, which the app and the Live Activity turn into the texts that a rider reads, and the name of the app.

## The name of the app

The name, TROME, is written once: `APP_NAME` in `ios/Config/Base.xcconfig`.
Never write it in a text: a view reads it with `@Environment(\.appName)` and passes it as `%@`, and a permission text in `ios/project.yml` writes `$(APP_NAME)`.
To rename the app, change that line and run `make strings-sync`.

## When make strings-check fails

| It says | Do this |
|---|---|
| `a build in Xcode would change: ...` | Run `make strings-sync`, then write the French texts of the new entries. |
| `no fr text marked "translated" for "..."` | Write the French text and mark it **translated**. A text that Xcode marked **Needs Review** after its English text changed: check it, then mark it **translated**. |
| `"..." is no longer in the code; remove it` | Delete the entry. |
| `app-name-sync: ... does not say ...` | A French permission text has an old name of the app: put the name in its place. |

The check makes sure that the catalogs in git are exactly the ones that Xcode writes, so that a build in Xcode changes no file.
Only a build in Xcode and `make strings-sync` change the catalogs; `make build`, `make run` and `make check` never do.
