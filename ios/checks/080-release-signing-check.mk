CHECKS += release-signing-check
CHECK_STEP_release-signing-check := release signing check
.PHONY: release-signing-check

help::
	@echo "make release-signing-check  Fail when Xcode would sign a Release build with no TROME_RELEASE_TEAM, or would not sign it automatically with one, or without the push capability and the app group of the silent start (no compile, no Apple account)"

# Not through the build gate: each build stops at the signing check, before any compile, in a few seconds.
release-signing-check: project
	@./scripts/release-signing-check.sh $(PROJECT) $(BUILD_DIR)/release-signing-check
	@./scripts/release-entitlements-check.py $(PROJECT)
