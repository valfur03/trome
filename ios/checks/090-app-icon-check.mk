CHECKS += app-icon-check
CHECK_STEP_app-icon-check := app icon check
.PHONY: app-icon-check

help::
	@echo "make app-icon-check      Fail when the app has no store icon of 1024 x 1024 pixels, or when its icon has an alpha channel"

app-icon-check:
	@./scripts/app-icon-check.py App/Assets.xcassets/AppIcon.appiconset
