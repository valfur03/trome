CHECKS += build
CHECK_STEP_build := build (no warning allowed)
.PHONY: build

help::
	@echo "make build               Build the app for the Simulator, with no warning allowed (make run builds it first)"

# With LIVE=1, Xcode keeps its copy of the build settings (the build description, in .build/DerivedData) until the path
# of an -xcconfig file changes, not its content. So PRIM_SECRETS_STAMP passes the time, the file number and the size of
# the key file (never its content): a new key changes the stamp, and Xcode reads the file again.
build: project
ifeq ($(LIVE),1)
	@test -f "$(PRIM_SECRETS)" || { echo "No PRIM key: $(PRIM_SECRETS) does not exist. Add the key there (see ios/README.md), or build without LIVE=1." >&2; exit 1; }
	@echo "LIVE=1: the build uses the PRIM key of $(PRIM_SECRETS)"
	@if [ "$(PRIM_SECRETS)" = "$(OLD_PRIM_SECRETS)" ]; then echo "Note: the key is at its old place. Once the main folder has the ios/ folder, move it there: cd $(MAIN_FOLDER) && mv Config/Secrets.xcconfig ios/Config/ && rmdir Config"; fi
	@$(BUILD_APP) -xcconfig "$(PRIM_SECRETS)" PRIM_SECRETS_STAMP="$$(stat -f '%Fm-%i-%z' "$(PRIM_SECRETS)")"
else ifeq ($(RELEASE),1)
	@rm -rf $(BUILD_RESULT)
	@$(BUILD_GATE) $(QUIET) $(LOGS)/build-release.log '' $(BUILD_RELEASE_APP) -resultBundlePath $(BUILD_RESULT)
	@xcrun xcresulttool get build-results --path $(BUILD_RESULT) | ./scripts/build-warnings.py
else
	@rm -rf $(BUILD_RESULT)
	@$(BUILD_GATE) $(QUIET) $(LOGS)/build.log '' $(BUILD_APP) $(NO_KEY) $(SILENT_START_COMPILED) -resultBundlePath $(BUILD_RESULT)
	@xcrun xcresulttool get build-results --path $(BUILD_RESULT) | ./scripts/build-warnings.py
endif
