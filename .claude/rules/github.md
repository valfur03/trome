---
paths:
  - ".github/workflows/**"
  - ".github/actions/**"
commands:
  - '^(\S*/)?gh(\s+(-R|--repo)\s+\S+|\s+--?\S+)*\s+(secret|variable)(\s|$)'
  - '^(\S*/)?gh(\s+(-R|--repo)\s+\S+|\s+--?\S+)*\s+workflow\s+(run|enable|disable)(\s|$)'
  - '^(\S*/)?gh(\s+(-R|--repo)\s+\S+|\s+--?\S+)*\s+run\s+rerun(\s|$)'
  - '^(\S*/)?gh(\s+(-R|--repo)\s+\S+|\s+--?\S+)*\s+api\s.*(environments|pending_deployments|deployment_protection_rules|secrets|variables|dispatches|rerun|rulesets|protection)'
---
# GitHub: secrets, environments, release and deploy workflows

These rules are for every agent that edits, reviews or merges a workflow of `.github/`, or runs a `gh` command that starts a workflow, answers a deployment, or touches a secret, a variable or an environment.
decision-107 and decision-108 decide them; doc-11 part 3 and doc-12 part 1 are the research.

Why they exist: the agents act on GitHub with the prompter's own login (his `gh` token, his SSH key), so GitHub lets an agent do all that he can do.
And the repo is public, so the log of a run is public, and a workflow that holds a secret can print it.
Until a technical wall exists (option C of doc-11, not chosen), these rules are the only guard.

A **release or deploy workflow** is a workflow of `.github/` that reads a secret other than `secrets.GITHUB_TOKEN` (the run's own token).
The app's TestFlight and App Store run and the server's deploy are such workflows.
The checks of the app, which hold no secret, and the docs site (`docs-site.yml`) are not.
The task that gives a secret to a script of a workflow adds that script to the `paths:` list of this rule, so that every edit and every diff of it brings this rule.

- **Never start a release or deploy workflow by hand**: no `gh workflow run`, no `gh run rerun`, no dispatch through `gh api`, no button of the web page.
  The manager's push of `main` is the only way an agent starts one.
  Why: it ships to riders with a secret, and the prompter's login would let any agent start it with no review.
  An agent may start a workflow that holds no secret (the checks), when its task needs a real run.
- **Never approve or reject a waiting deployment** (`gh api .../pending_deployments`, the web page).
  Why: the approval of the app's signing environment is the prompter's click on the first three App Store releases (decision-108 point 4), and GitHub cannot tell an agent from him.
  The server's deploy has no required reviewer (decision-108 point 1), so it has no deployment to answer.
- **Never set, change or delete a secret or a variable**, of the repo or of an environment (`gh secret`, `gh variable`, `gh api .../secrets` or `.../variables`).
  Only the prompter sets them, from his own terminal.
  Why: the value would pass through the agent's context, and its logs.
- **Never change an environment**: never create or delete one, never change its required reviewers, its wait timer or its branch rule, and never change the rules of a branch.
  Why: these settings are the only check that GitHub makes before it gives a secret to a job.
- **Never print a secret from a run.** No step echoes a secret, a part of it, its length or an encoding of it (`base64`), or writes it to the summary, an output or an artifact.
  A secret goes only to the steps that need it, never to a step that installs packages or runs tests.
  Why: GitHub hides only the exact value in a log; a part or an encoding of it is public at once.

## The review of a release or deploy workflow

A change of a release or deploy workflow, or of a script that such a workflow runs with a secret, merges with no yes from the prompter.
The team's review is the only guard, so the reviewer checks it, file by file (the prompter's order of 2026-10-14, doc-3).
How you know that a change is one: `git diff main...task/<id>` shows a file of `.github/` whose text, before or after the change, names `secrets.` other than `secrets.GITHUB_TOKEN` (`grep -n 'secrets\.'` on both versions), or a file of the `paths:` list of this rule outside `.github/`.

- **Each secret reaches only the steps that use it** (sign, upload, deploy): in the `env:` or `with:` of those steps, never of the job or the workflow, never in a step that installs packages or runs tests, and never printed (the clause above).
- **No new secret**: each name of `secrets.` in the diff is one that the task names; a new one is a finding, since only the prompter can set it.
- **Only `main` gets a secret**: the job that holds one names its `environment:` (whose branch rule is `main` only) and has an `if:` on `github.ref == 'refs/heads/main'`, and the workflow has no `pull_request` or `pull_request_target` trigger.
  Why: a manual start can run any branch, and a branch can hold changed code.
- **The App Store click stays**: the release job keeps the environment of the signing, and no step or token can answer a waiting deployment.
- **Third-party actions are pinned**: in a job that holds a secret, each `uses:` that is not `actions/...` names a full commit SHA.
  Why: a tag can be moved to new code, which then runs with the secret.

The reviewer writes one line per check in the task notes, with what it saw; a failed check is a high finding.
