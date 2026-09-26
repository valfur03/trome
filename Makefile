PROJECT := RATPActivity.xcodeproj
APP_SCHEME := RATPActivity
E2E_SCHEME := RATPActivityE2E
BUILD_DIR := .build
DERIVED_DATA := $(BUILD_DIR)/DerivedData
APP_PATH := $(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/RATPActivity.app
E2E_RESULT := $(BUILD_DIR)/e2e.xcresult
DOCS_SCHEME := RATPActivityDocsScreenshots
DOCS_SCREENSHOTS_RESULT := $(BUILD_DIR)/docs-screenshots.xcresult
DOCS_DIR := docs
DOCS_BASE ?= develop
PORT ?= 4321
SIMULATOR := ./scripts/simulator.sh
SIM_LOCK := ./scripts/sim-lock.sh
CORE_PACKAGE := Packages/RATPCore
NO_KEY := -xcconfig Config/NoKey.xcconfig
LIVE_XCCONFIG := $(BUILD_DIR)/Live.xcconfig
PRIM_SECRETS ?= $(shell git worktree list --porcelain | sed -n '1s/^worktree //p')/Config/Secrets.xcconfig

ifeq ($(LIVE),1)
ifneq ($(filter-out build run,$(MAKECMDGOALS)),)
$(error LIVE=1 works only with 'make build' and 'make run')
endif
endif

XCODEBUILD := xcodebuild -quiet \
	-project $(PROJECT) \
	-derivedDataPath $(DERIVED_DATA) \
	-clonedSourcePackagesDirPath $(BUILD_DIR)/SourcePackages
BUILD_APP := $(XCODEBUILD) -scheme $(APP_SCHEME) -destination 'generic/platform=iOS Simulator' build

.PHONY: help setup generate project lint lint-fix build test check live-key-check run e2e stations simulator simulator-shutdown simulator-delete simulator-delete-old clean docs docs-dev docs-check docs-check-if-changed docs-install docs-stop node-check docs-screenshots

help:
	@echo "make setup               Install the tools and create the Xcode project"
	@echo "make generate            Create the Xcode project again (after a change in project.yml)"
	@echo "make run                 Build the app and open it in the shared Simulator (keeps the Simulator lock)"
	@echo "make run LIVE=1          Same, with the real PRIM key of the main repo folder (QA only, see CLAUDE.md)"
	@echo "make check               Quality gate: lint + key leak check + build + unit tests (+ make docs-check if docs/ changed)"
	@echo "make test                Unit tests only (on the Mac, no Simulator)"
	@echo "make live-key-check      Prove that a LIVE=1 build does not print the key (uses a fake key)"
	@echo "make e2e                 End-to-end tests on the shared Simulator (takes the Simulator lock)"
	@echo "make lint-fix            Fix the lint problems that can be fixed automatically"
	@echo "make stations            Download the metro and RER station list again"
	@echo "make simulator           Print the ID of the shared Simulator (creates it if needed)"
	@echo "make simulator-shutdown  Remove the app of 'make run' from the Simulator and free the lock (the Simulator shuts down when idle)"
	@echo "make simulator-delete    Delete the shared Simulator (takes the Simulator lock)"
	@echo "make simulator-delete-old  Delete the old Simulators of each folder (takes the Simulator lock)"
	@echo "make clean               Delete the build folder and the Xcode project"
	@echo "make docs                Build the docs site and serve it at http://localhost:4321 (PORT=<n> for another port)"
	@echo "make docs-dev            Serve the docs with live reload, no search (PORT=<n> for another port)"
	@echo "make docs-stop           Stop the docs server of this folder (when it runs in the background)"
	@echo "make docs-check          Docs quality gate: unit tests + astro check + build + internal link check"
	@echo "make docs-screenshots    Take the app screenshots of the docs on the shared Simulator (takes the Simulator lock)"

setup:
	@command -v xcodegen > /dev/null || brew install xcodegen
	@command -v swiftlint > /dev/null || brew install swiftlint
	@command -v pngquant > /dev/null || brew install pngquant
	@$(MAKE) generate

generate:
	xcodegen generate --quiet

project:
	@xcodegen generate --use-cache --quiet

lint:
	swiftlint lint --strict --quiet

lint-fix:
	swiftlint --fix --quiet
	swiftlint lint --strict --quiet

build: project
ifeq ($(LIVE),1)
	@test -f "$(PRIM_SECRETS)" || { echo "No PRIM key: $(PRIM_SECRETS) does not exist. Add the key there (see README), or build without LIVE=1." >&2; exit 1; }
	@echo "LIVE=1: the build uses the PRIM key of $(PRIM_SECRETS)"
	@mkdir -p $(BUILD_DIR)
	@trap 'rm -f $(LIVE_XCCONFIG)' EXIT INT TERM; \
		printf '#include "%s"\n' "$(PRIM_SECRETS)" > $(LIVE_XCCONFIG) && $(BUILD_APP)
else
	@rm -f $(LIVE_XCCONFIG)
	$(BUILD_APP) $(NO_KEY)
endif

test:
	swift test --quiet --package-path $(CORE_PACKAGE) --scratch-path $(BUILD_DIR)/RATPCore

check: lint live-key-check build test docs-check-if-changed

live-key-check: project
	@./scripts/live-key-check.sh

run: build
	@$(SIM_LOCK) open $(SIMULATOR) launch "$(APP_PATH)"

e2e: project
	@rm -rf $(E2E_RESULT)
	$(SIM_LOCK) job $(SIMULATOR) reset $(XCODEBUILD) $(NO_KEY) -scheme $(E2E_SCHEME) \
		-destination "platform=iOS Simulator,name=$$($(SIMULATOR) name)" \
		-parallel-testing-enabled NO -collect-test-diagnostics never \
		-test-timeouts-enabled YES -default-test-execution-time-allowance 300 \
		-resultBundlePath $(E2E_RESULT) test \
		|| { status=$$?; ./scripts/e2e-failures.py $(E2E_RESULT); exit $$status; }

stations:
	python3 scripts/update-stations.py

simulator:
	@$(SIMULATOR) udid

simulator-shutdown:
	@$(SIM_LOCK) free

simulator-delete:
	@$(SIM_LOCK) job $(SIMULATOR) delete

simulator-delete-old:
	@$(SIM_LOCK) job $(SIMULATOR) delete-old

clean:
	rm -rf $(BUILD_DIR) $(PROJECT)

node-check:
	@./scripts/node-check.sh

docs-install: node-check
	@if [ ! -f $(DOCS_DIR)/node_modules/.package-lock.json ] || [ $(DOCS_DIR)/package-lock.json -nt $(DOCS_DIR)/node_modules/.package-lock.json ]; then \
		cd $(DOCS_DIR) && npm ci; \
	fi

docs: docs-install
	cd $(DOCS_DIR) && npm run build && npm run preview -- --port $(PORT)

docs-dev: docs-install
	cd $(DOCS_DIR) && npm run dev -- --port $(PORT)

docs-stop: node-check
	@if [ -d $(DOCS_DIR)/node_modules ]; then \
		cd $(DOCS_DIR) && npx --no-install astro preview stop && npx --no-install astro dev stop; \
	fi

docs-check: docs-install
	cd $(DOCS_DIR) && npm test && npm run check && npm run build

docs-check-if-changed:
	@if ./scripts/docs-changed.sh $(DOCS_BASE); then \
		$(MAKE) docs-check; \
	else \
		echo "docs/ has no change since $(DOCS_BASE): skipping make docs-check"; \
	fi

docs-screenshots: project
	$(SIM_LOCK) job $(SIMULATOR) reset ./scripts/docs-screenshots.sh $(DOCS_SCREENSHOTS_RESULT) \
		$(XCODEBUILD) $(NO_KEY) -scheme $(DOCS_SCHEME) \
		-destination "platform=iOS Simulator,name=$$($(SIMULATOR) name)" \
		-parallel-testing-enabled NO -collect-test-diagnostics never \
		-test-timeouts-enabled YES -default-test-execution-time-allowance 300
