CHECKS += bundle-id-check
CHECK_STEP_bundle-id-check := bundle ID check
.PHONY: bundle-id-check

help::
	@echo "make bundle-id-check     Fail when a Debug build could carry the App Store bundle ID (also with the Debug IDs of Local.xcconfig set), or when a Release build is signed automatically with no TROME_RELEASE_TEAM"

bundle-id-check: project
	@./scripts/bundle-id-check.sh $(PROJECT)
