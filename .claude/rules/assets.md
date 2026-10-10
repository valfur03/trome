---
paths:
  - "ios/App/**"
  - "ios/Widget/**"
  - "ios/Packages/TROMECore/Sources/TROMECore/LiveActivity/**"
  - "ios/Packages/TROMECore/Sources/TROMEBadge/**"
  - "ios/Config/Base.xcconfig"
  - "ios/DocsScreenshots/**"
  - "ios/scripts/docs-screenshots.sh"
  - "ios/scripts/store-screenshots.sh"
  - "ios/scripts/store-screenshots-compose.swift"
  - "ios/guide/assets.md"
  - "docs/src/content/**"
  - "docs/src/assets/**"
  - "video/**"
commands:
  - '^(\S*/)?make\b.*\srun(\s|$)'
---
# The assets follow the app

These rules are for every change of the app screen, the Live Activity, the Dynamic Island, a text or the docs, and for its review and its QA.
The assets show the app outside the app: the docs pictures and pages, the store screenshots, the store text and the store video.
`ios/guide/assets.md` lists each asset, what it shows, and how to make it again.
Why: a store page or a video that shows a screen the app no longer has misleads a rider before the install, and App Review refuses what does not show the app (doc-1, "Marketing assets stay true to the app"; decision-68).

- **A change that makes an asset false updates it, in the same task:** the docs pictures and pages, the store screenshots, the store text.
  Why: the engineer of the change knows what changed; an asset left for later is forgotten.
- **A change that ships, cuts or defers a behaviour that the vision names** also swaps the page sentences that the ledger lists for it, in the same merge (`.claude/rules/writing.md`, "A page is compared with the vision").
  Why: an asset can match the app and still sell a way of working that the vision is replacing.
- **The video is the exception: the engineer never touches it.** It costs the most to make again, so it changes only for a big change, and the Product Owner decides.
  A change is big for the video when a viewer would see another app: the look of the screen, the flow of the first use, the name or the icon, a feature that the video shows or says is there.
  A fix, a new row that the video never shows, or a text in a corner is not.
- **End the task notes with the line of the assets,** one of these (both lines when both are true):
  - `Assets: checked, none shown changed`
  - `Assets: <which> updated`
  - `Video: shows <thing> and this change alters it, PO call`

  Why: the Product Owner reads these lines at each roadmap review (doc-5), and a missing line hides a false asset.
- **The Product Owner's call for the video:** update it now, update it with the next big change, or take the preview off the store page until it is true again, because a false video is worse than an old one.
  The PO writes the reason in the ticket.
- **The reviewer and QA check the line.** When a changed screen or text is one that an asset shows, and the line is missing or wrong, say so in the review: a medium finding, like a file in the wrong place.
- **A new asset:** the change that makes it adds its row to the list, and the folder of its source to the `paths:` of this rule.
