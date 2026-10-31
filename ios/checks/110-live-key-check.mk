CHECKS += live-key-check
CHECK_STEP_live-key-check := key leak check (with the upload checks of the Release app)
.PHONY: live-key-check

help::
	@echo "make live-key-check      Prove that a LIVE=1 build does not print the key, that a new key replaces the old one, that a Release build holds the app token of the server but never the PRIM key, that a Release build with no server host or no app token fails, and that the Release app passes the upload checks of App Store Connect: an icon of 1024 x 1024 pixels with no transparent pixel, a privacy manifest with a reason for each required reason API that its code uses, the answer on encryption, a version such as 1.0.0, no placeholder address (uses fake values)"

live-key-check: project
	@TROME_SHARED_CACHE="$(TROME_SHARED_CACHE)" ./scripts/live-key-check.sh
