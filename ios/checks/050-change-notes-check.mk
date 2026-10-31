CHECKS += change-notes-check
CHECK_STEP_change-notes-check := change notes check
.PHONY: change-notes-check

help::
	@echo "make change-notes-check  Fail when a note of ios/changes/ breaks its format, or when the commits since main change the code of the app with no note and no commit title that ends with \"(no rider change)\" (part of make check)"

change-notes-check:
	@./scripts/change-notes-check.py check
