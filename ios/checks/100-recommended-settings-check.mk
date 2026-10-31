CHECKS += recommended-settings-check
CHECK_STEP_recommended-settings-check := recommended settings check
.PHONY: recommended-settings-check

help::
	@echo "make recommended-settings-check  Fail when the installed Xcode is newer than the one that last checked the project settings"

recommended-settings-check:
	@./scripts/recommended-settings-check.sh project.yml "$$(xcodebuild -version | head -1)"
