IOS_TARGETS := setup generate project git-hooks git-hooks-off lint lint-fix build strings-check strings-sync prose-check public-text-check bundle-id-check test test-scripts live-key-check recommended-settings-check run switch-language e2e stations simulator \
	simulator-shutdown simulator-delete simulator-delete-old clean clean-shared-cache docs-screenshots live-activity-render merge
DOCS_TARGETS := docs docs-dev docs-stop docs-check docs-check-if-changed
SERVER_TARGETS := server-setup server-check server-check-if-changed server-dev server-stop server-login server-secrets server-secret server-counts server-deploy-staging server-deploy
SUB_MAKE := $(MAKE) --no-print-directory

.PHONY: help check $(IOS_TARGETS) $(DOCS_TARGETS) $(SERVER_TARGETS)

help:
	@echo "Run each command from here (the root). It runs in the folder of its part: ios/, docs/ or server/."
	@echo "make check               Quality gate: the iOS gate (lint + Markdown line check + public text check + bundle ID check + recommended settings check + key leak check + build with no warning + strings check + unit tests + script tests) + make docs-check if docs/ changed + make server-check if server/ or contracts/ changed"
	@echo "make <command> VERBOSE=1  Print every line of each step as it runs; without VERBOSE=1, a step that passes prints one line (with its counts and time), a step that fails prints its whole output, and each step keeps its output in .build/logs/ of its part"
	@$(SUB_MAKE) -C ios help | grep -v '^make check '
	@$(SUB_MAKE) -C docs help
	@$(SUB_MAKE) -C server help

check:
	@$(SUB_MAKE) -C ios check
	@$(SUB_MAKE) -C docs docs-check-if-changed
	@$(SUB_MAKE) -C server server-check-if-changed

$(IOS_TARGETS):
	@$(SUB_MAKE) -C ios $@

$(DOCS_TARGETS):
	@$(SUB_MAKE) -C docs $@

$(SERVER_TARGETS):
	@$(SUB_MAKE) -C server $@
