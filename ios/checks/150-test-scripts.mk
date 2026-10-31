CHECKS += test-scripts
CHECK_STEP_test-scripts := script tests
.PHONY: test-scripts

help::
	@echo "make test-scripts        Tests of the scripts: the Simulator lock (with a fake xcrun, no Simulator) and the warning checks"

# A script test that compiles runs itself through the build gate; the guard, first on PATH, fails a swift, swiftc or xcodebuild (also through xcrun) outside it.
test-scripts:
	@mkdir -p $(LOGS)
	@count=0; guard_log=$(CURDIR)/$(LOGS)/test-scripts-swift.log; for test in ./scripts/tests/*-test.sh; do \
		: > $$guard_log; \
		status=0; PATH="$(CURDIR)/scripts/tests/gate-guard:$$PATH" RATP_SWIFT_GUARD_LOG=$$guard_log $$test > $(LOGS)/test-scripts.log 2>&1 || status=$$?; \
		[ ! -s $$guard_log ] || { cat $$guard_log; echo "test-scripts: FAILED: $$test runs these compiles outside the build gate: run it through ./scripts/build-gate.py build"; exit 1; }; \
		[ $$status -eq 0 ] || { cat $(LOGS)/test-scripts.log; echo "test-scripts: FAILED: $$test (its whole output is above, and in ios/$(LOGS)/test-scripts.log)"; exit 1; }; \
		count=$$((count + 1)); \
	done; \
	echo "test-scripts: OK ($$count script tests)"
