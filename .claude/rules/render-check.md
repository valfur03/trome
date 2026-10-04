---
paths:
  - "ios/Widget/**"
  - "ios/RenderCheck/**"
  - "ios/Packages/TROMECore/Sources/TROMECore/LiveActivity/**"
  - "ios/scripts/live-activity-render*"
  - "ios/scripts/tests/live-activity-render-test.sh"
commands:
  - '^(\S*/)?make\b.*\slive-activity-render(\s|$)'
---
# The Live Activity render check

These rules are for a change to the Live Activity views or their data, and for every run of the render check.

`make live-activity-render` draws the Live Activity views (the lock screen and the bottom region of the expanded Dynamic Island) for every station and page, at both phone widths and at the Large and XXXL text sizes.
It lists the drawings that are too tall, the cut texts and the breaches of decision-15, and saves images for a person to read (`ios/guide/render-check.md`).

- **When to run it.** In any task that changes the Live Activity views or their data (`ios/Widget/`, `LinesPage`, `ContentState`), for example TASK-36, TASK-65 and TASK-37: once before the change and once after it.
  Look at each image once, write what it shows in the task notes, and do not read the same image again unless it changed: each image that you read stays in the context of every later call.
  Write in the task notes, before and after the change, the number of too tall drawings and the counts of each kind of breach of decision-15 (the summary prints them for each phone, surface and text size), and the cut texts that changed, and put the images that matter in the notes for the reviewer and QA.
  Do not write a temporary UI test for this any more.
- **The breaches of decision-15.** decision-15 is the product rule of what may be cut in a row of the Live Activity.
  The render check lists the texts that break it, in the images: (a) a time that is cut (for example "dans 3…"); (b) a destination shown with fewer than 6 characters before its "…" (a destination shorter than 6 characters that is shown whole is not a breach); (c) the two directions of one line that show the same text (for example "Mairie d'…" twice); (d) a station label name that is cut.
  It knows which text is cut from SwiftUI's own layout of each text (`Text.LayoutKey`: cut or not, and how many characters show), and which text it is from the text recognition of the Mac on that part of the image, compared with the texts of the drawn state.
  A breach is a defect to write in the task notes: the Product Owner decides case by case (decision-15).
  "Other cut texts" (for example "Ouvrez l'app pour mettre à jour les horaires") are not breaches: a person reads them in `cut-texts.txt`.
- **It is not a gate.** It is not part of `make check` or `make e2e`, and it fails only when it cannot run, even with breaches.
  Why: decision-15 keeps it a report until option C (decision-14) is shipped, because C redraws these views.
  Making it a gate is not for a Live Activity task to decide.
- **French, and English on demand.** It draws in French (the main language), in `ios/.build/live-activity-render/fr/`.
  `make live-activity-render ENGLISH=1` draws in English too, in `.../en/`: use it only when the task changes an English text of the Live Activity.
  Why: the English run costs about 130 s more of the shared Simulator, and on 2026-09-29 it found nothing that the French run did not find (the French texts are longer).
  Write the numbers of each language that you drew in the notes.
  The views get their texts from a small host app, `ios/RenderCheck/Host/`, that holds the String Catalog of the widget, as the widget extension does.
  Why: a test bundle with no app finds no texts, so it drew only the English texts of the code, and it missed the French cuts of TASK-112.
  The test fails when the texts are not in the language that it draws.
  A new String Catalog of the widget goes in this host app too (`ios/project.yml`).
- **Its two entry views.** It draws `LockScreenView(state:isStale:)` and `ExpandedIslandBottomRegion(state:isStale:)` of `ios/Widget/StationLiveActivity.swift`.
  Keep them `internal` with these parameters.
  A redesign may change what is inside them.
- **Its numbers.** The widths and the height limits in `ios/RenderCheck/LiveActivityRenderCheck.swift` were measured on the real Live Activity (TASK-124).
  A task that changes the regions of the Dynamic Island, or a new iOS version, measures them again before it trusts the check.
- It is a Simulator job, through the lock, like `make docs-screenshots`.
  It frees the lock when the drawing ends.
