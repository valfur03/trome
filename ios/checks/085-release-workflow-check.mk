CHECKS += release-workflow-check
CHECK_STEP_release-workflow-check := release workflow check
.PHONY: release-workflow-check

help::
	@echo "make release-workflow-check  Fail when the release workflow could give a secret before the approval at its environment, on a branch other than main, or before the E2E proof, could print a value in its public log, keeps an artifact, or runs an action not pinned to a commit hash (reads the file only)"

release-workflow-check:
	@./scripts/release-workflow-check.py ../.github/workflows/release.yml
