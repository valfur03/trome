CHECKS += test-waits
CHECK_STEP_test-waits := unit tests in the paces of a busy Mac
.PHONY: test-waits

help::
	@echo "make test-waits          Run the tests of the unit test files changed since main 3 times as on a busy Mac where the code runs late, and 3 times where the test runs late: fails a test that passes only on a quiet Mac (ALL=1: every unit test; part of make check)"

# Through the build gate: each run compiles nothing new, but runs the tests on every core.
test-waits:
	@$(BUILD_GATE) $(QUIET) $(LOGS)/test-waits.log 'test-waits:' ./scripts/test-waits.py run
