CHECKS += test
CHECK_STEP_test := unit tests
.PHONY: test

help::
	@echo "make test                Unit tests only (on the Mac, no Simulator)"

test:
	@$(BUILD_GATE) $(QUIET) $(LOGS)/unit-tests.log 'Test run with|Executed [1-9]' swift test --quiet --package-path $(CORE_PACKAGE) --scratch-path $(BUILD_DIR)/TROMECore -Xswiftc -warnings-as-errors
