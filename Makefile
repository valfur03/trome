IOS_TARGETS := setup generate project lint lint-fix build strings-check strings-sync test test-scripts live-key-check recommended-settings-check run switch-language e2e stations simulator \
	simulator-shutdown simulator-delete simulator-delete-old clean clean-shared-cache docs-screenshots merge
DOCS_TARGETS := docs docs-dev docs-stop docs-check docs-check-if-changed
SUB_MAKE := $(MAKE) --no-print-directory

.PHONY: help check $(IOS_TARGETS) $(DOCS_TARGETS)

help:
	@echo "Run each command from here (the root). It runs in the folder of its part: ios/ or docs/."
	@echo "make check               Quality gate: the iOS gate (lint + recommended settings check + key leak check + build with no warning + strings check + unit tests + script tests) + make docs-check if docs/ changed"
	@$(SUB_MAKE) -C ios help | grep -v '^make check '
	@$(SUB_MAKE) -C docs help

check:
	@$(SUB_MAKE) -C ios check
	@$(SUB_MAKE) -C docs docs-check-if-changed

$(IOS_TARGETS):
	@$(SUB_MAKE) -C ios $@

$(DOCS_TARGETS):
	@$(SUB_MAKE) -C docs $@
