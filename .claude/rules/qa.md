---
paths:
  - ".claude/rules/qa.md"
commands:
  - '^(\S*/)?make\b.*\s(run|switch-language)(\s|$)'
---
# QA: French first

These rules are for QA, and for any check of the app by hand in the Simulator.

Almost every user of the app is French.
So French is the main language of QA.

- **The main pass is in French.** QA runs `make run LANGUAGE=fr` (with `LIVE=1` or `SMALL=1` when needed).
  The whole Simulator is then in French.
  QA's main pass through each screen, the Live Activity (lock screen), the Dynamic Island, the notifications and the permission messages is in French.
- **Then a quick look in English, at the changed screens only.** After the main pass, QA runs `make switch-language LANGUAGE=en`.
  It puts the Simulator in English and opens the app again, with its data and its permissions, so QA does not set up the app again.
  It uses the Simulator of the `make run` (also with `SMALL=1`).
  A notification sent before the switch keeps its old language: this is not a bug.
  QA looks only at the screens, the Live Activity views, the notifications and the messages that the task changed: a text that is not translated, a text in the wrong language, or a layout problem with the English text (English and French texts do not have the same length).
  Keep this look short: it must not make the QA run longer.
  When the task changes no text and no screen, skip it.
  With `LIVE=1`, the app keeps calling PRIM in English too: these calls count in the budget of the QA run (`.claude/rules/live-data.md`).
  Then QA runs `make simulator-shutdown` at once.
  `make switch-language LANGUAGE=fr` goes back to French.
- **What is a bug.** A screen or a message that mixes French and English.
  A French text that a Paris rider would not say (the words of the RATP signage and of iOS in French are the reference: "Prochains passages", "écran verrouillé", "Réglages").
  The "Testing tools" screen, the "Testing tools" link and the "Fake position" banner of the main screen (debug builds only) stay in English: this is not a bug.
- The system popups (for example "Autoriser une fois") come from iOS in the language of the Simulator.
  Only their explanation text comes from the app.
- `make e2e`, `make docs-screenshots` and `make store-screenshots` put the Simulator back in English by themselves.
- **Screenshots.** Look at each screenshot once, write what it shows in your QA notes, and do not read the same picture again unless the screen changed: each picture that you read stays in the context of every later call.
