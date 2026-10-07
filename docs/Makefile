DOCS_BASE ?= main
PORT ?= 4321
QUIET := ../ios/scripts/quiet.sh
LOGS := .build/logs

.PHONY: help node-check docs-install docs docs-dev docs-stop docs-check docs-check-if-changed

help:
	@echo "make docs                Build the docs site (stops on a new warning) and serve it at http://localhost:4321/ (PORT=<n> for another port)"
	@echo "make docs-dev            Serve the docs with live reload, no search (PORT=<n> for another port)"
	@echo "make docs-stop           Stop the docs server of this folder (when it runs in the background)"
	@echo "make docs-check          Docs quality gate: unit tests + astro check + build + internal link check, and no warning"

node-check:
	@./scripts/node-check.sh

docs-install: node-check
	@if [ ! -f node_modules/.package-lock.json ] || [ package-lock.json -nt node_modules/.package-lock.json ]; then \
		$(QUIET) $(LOGS)/docs-install.log 'added [0-9]+ packages' npm ci; \
	fi

docs: docs-install
	node scripts/build-check.ts && npm run preview -- --port $(PORT)

docs-dev: docs-install
	npm run dev -- --port $(PORT)

docs-stop: node-check
	@if [ -d node_modules ]; then \
		npx --no-install astro preview stop && npx --no-install astro dev stop; \
	fi

docs-check: docs-install
	@$(QUIET) $(LOGS)/docs-unit-tests.log '^ℹ (tests|fail) ' npm test
	@$(QUIET) $(LOGS)/astro-check.log '^- [0-9]+ (errors|warnings)' npm run check
	@$(QUIET) $(LOGS)/docs-build.log '\[build\] [0-9]+ page|^The docs build printed' node scripts/build-check.ts

docs-check-if-changed:
	@if ./scripts/docs-changed.sh $(DOCS_BASE); then \
		$(MAKE) docs-check; \
	else \
		echo "docs/ has no change since $(DOCS_BASE): skipping make docs-check"; \
	fi
