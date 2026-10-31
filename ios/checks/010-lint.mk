CHECKS += lint
CHECK_STEP_lint := lint
.PHONY: lint

help::
	@echo "make lint                Lint the Swift code with SwiftLint, with no warning allowed"

lint:
	@$(QUIET) $(LOGS)/lint.log '' swiftlint lint --strict --quiet
