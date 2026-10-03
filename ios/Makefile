PROJECT := TROME.xcodeproj
OLD_PROJECT := RATPActivity.xcodeproj
APP_SCHEME := TROME
E2E_SCHEME := TROMEUITests
BUILD_DIR := .build
DERIVED_DATA := $(BUILD_DIR)/DerivedData
APP_NAME := $(shell sed -n -E 's/^APP_NAME = (.+)$$/\1/p' Config/Base.xcconfig)
APP_PATH := $(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/$(APP_NAME).app
E2E_RESULT := $(BUILD_DIR)/e2e.xcresult
XCODEGEN_CACHE := $(BUILD_DIR)/xcodegen-cache
E2E_TARGET := TROMEUITests
E2E_ONLY := $(foreach test,$(ONLY),-only-testing:$(E2E_TARGET)/$(test))
DOCS_SCHEME := TROMEDocsScreenshots
DOCS_SCREENSHOTS_RESULT := $(BUILD_DIR)/docs-screenshots.xcresult
RENDER_SCHEME := TROMERenderCheck
RENDER_OUT := $(BUILD_DIR)/live-activity-render
BUILD_RESULT := $(BUILD_DIR)/build.xcresult
SIMULATOR := ./scripts/simulator.sh
SIM_LOCK := ./scripts/sim-lock.sh
CORE_PACKAGE := Packages/TROMECore
NO_KEY := -xcconfig Config/NoKey.xcconfig
MAIN_FOLDER = $(shell git worktree list --porcelain | sed -n '1s/^worktree //p')
OLD_PRIM_SECRETS = $(MAIN_FOLDER)/Config/Secrets.xcconfig
PRIM_SECRETS ?= $(firstword $(wildcard $(MAIN_FOLDER)/ios/Config/Secrets.xcconfig $(OLD_PRIM_SECRETS)) $(MAIN_FOLDER)/ios/Config/Secrets.xcconfig)
RATP_SHARED_CACHE ?= $(HOME)/Library/Caches/RATPActivity
HOST_ARCH := $(shell uname -m)

ifeq ($(SMALL),1)
ifneq ($(filter-out run,$(MAKECMDGOALS)),)
$(error SMALL=1 works only with 'make run')
endif
export RATP_SIM_SIZE := small
endif

ifeq ($(ENGLISH),1)
ifneq ($(filter-out live-activity-render,$(MAKECMDGOALS)),)
$(error ENGLISH=1 works only with 'make live-activity-render')
endif
export RENDER_LANGUAGES := fr en
endif

ifeq ($(origin LANGUAGE),command line)
ifneq ($(filter-out run switch-language,$(MAKECMDGOALS)),)
$(error LANGUAGE= works only with 'make run' and 'make switch-language')
endif
export RATP_SIM_LANGUAGE := $(LANGUAGE)
else ifneq ($(filter switch-language,$(MAKECMDGOALS)),)
$(error Say the language: make switch-language LANGUAGE=en (or LANGUAGE=fr))
endif

ifeq ($(LIVE),1)
ifneq ($(filter-out build run,$(MAKECMDGOALS)),)
$(error LIVE=1 works only with 'make build' and 'make run')
endif
USE_SHARED_CACHE :=
SHARED_SDK_MODULES :=
else
USE_SHARED_CACHE := ./scripts/shared-cache.sh use "$(RATP_SHARED_CACHE)"
SHARED_SDK_MODULES := SDK_EXPLICIT_MODULES_OUTPUT_PATH="$(RATP_SHARED_CACHE)/SDKExplicitPrecompiledModules"
endif

XCODEBUILD := $(USE_SHARED_CACHE) xcodebuild -quiet \
	-project $(PROJECT) \
	-derivedDataPath $(DERIVED_DATA) \
	-clonedSourcePackagesDirPath $(BUILD_DIR)/SourcePackages \
	COMPILER_INDEX_STORE_ENABLE=NO $(SHARED_SDK_MODULES) \
	SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES
BUILD_APP := $(XCODEBUILD) -scheme $(APP_SCHEME) -destination 'generic/platform=iOS Simulator' ARCHS=$(HOST_ARCH) build
EXPORT_STRINGS := $(XCODEBUILD) $(NO_KEY) -scheme $(APP_SCHEME) CODE_SIGNING_ALLOWED=NO \
	-exportLocalizations -localizationPath $(BUILD_DIR)/Localizations -exportLanguage fr
STRING_CATALOGS = $(wildcard App/*.xcstrings Widget/*.xcstrings)
REMOVE_OLD_PROJECT := if [ -e $(OLD_PROJECT) ]; then rm -rf $(OLD_PROJECT) && echo "Removed the old Xcode project ios/$(OLD_PROJECT): open ios/$(PROJECT) instead"; fi

.PHONY: help setup generate project git-hooks git-hooks-off lint lint-fix build strings-check strings-sync prose-check public-text-check bundle-id-check test test-scripts check live-key-check recommended-settings-check run switch-language e2e stations simulator simulator-shutdown simulator-delete simulator-delete-old clean clean-shared-cache docs-screenshots live-activity-render merge

help:
	@echo "make setup               Install the tools and create the Xcode project"
	@echo "make generate            Create the Xcode project again (after a change in project.yml or ios/Config), and refuse the App Store IDs in the Debug IDs of ios/Config"
	@echo "make git-hooks           Turn on the git hooks: after a git pull or a checkout in the main folder, the Xcode project is created again"
	@echo "make git-hooks-off       Turn off the git hooks"
	@echo "make run                 Build the app and open it in the shared Simulator (keeps the Simulator lock)"
	@echo "make run LIVE=1          Same, with the real PRIM key of the main repo folder (QA only, see CLAUDE.md)"
	@echo "make run SMALL=1         Same, on the smallest supported iPhone (an iPhone SE, 375 x 667 pt; keeps the Simulator lock)"
	@echo "make run LANGUAGE=fr     Same, with the Simulator in French (the default is English: LANGUAGE=en)"
	@echo "make switch-language LANGUAGE=en  After make run: put the Simulator in this language (en or fr) and open the app again, with its data"
	@echo "make check               iOS quality gate: lint + Markdown line check + public text check + bundle ID check + recommended settings check + key leak check + build (no warning allowed) + strings check + unit tests + script tests"
	@echo "make strings-check       Fail when a build in Xcode would change a String Catalog, when a text of the app or the Live Activity has no French text, or when a French permission text does not say APP_NAME"
	@echo "make strings-sync        Update the String Catalogs as a build in Xcode does (new texts, texts no longer in the code), and put APP_NAME of Config/Base.xcconfig in the permission texts"
	@echo "make prose-check         Fail when a line of prose of a Markdown or MDX file of the repo is longer than 400 characters (write one sentence per line)"
	@echo "make public-text-check   Fail when a file of the repo has a backlog id, a word of the team's own process, a personal email address, a local path or the old name of the app"
	@echo "make test                Unit tests only (on the Mac, no Simulator)"
	@echo "make test-scripts        Tests of the scripts: the Simulator lock (with a fake xcrun, no Simulator) and the warning checks"
	@echo "make live-key-check      Prove that a LIVE=1 build does not print the key, that a new key replaces the old one, that a Release build holds the app token of the server but never the PRIM key, and that a Release build with no server host or no app token fails (uses fake values)"
	@echo "make bundle-id-check     Fail when a Debug build could carry the App Store bundle ID (also with the Debug IDs of Local.xcconfig set), or when a Release build is signed automatically"
	@echo "make recommended-settings-check  Fail when the installed Xcode is newer than the one that last checked the project settings"
	@echo "make e2e                 End-to-end tests on the shared Simulator (takes the Simulator lock)"
	@echo "make e2e ONLY=<TestClass>  Only these E2E test classes (or Class/testMethod), separated by spaces"
	@echo "make merge               Merge the branch of this folder into main (after the review and QA), with the Simulator lock all along: rebase, make check, full make e2e, fast-forward"
	@echo "make lint-fix            Fix the lint problems that can be fixed automatically"
	@echo "make stations            Download the metro and RER station list again"
	@echo "make simulator           Print the ID of the Simulator of this folder after make run, else of RATP-Shared (creates it if needed)"
	@echo "make simulator-shutdown  Remove the app of 'make run' from the Simulator and free the lock (the Simulator shuts down when idle)"
	@echo "make simulator-delete    Delete the shared Simulators, also those of a second-slot trial (waits until no other Simulator job runs)"
	@echo "make simulator-delete-old  Delete the old Simulators of each folder (takes the Simulator lock)"
	@echo "make clean               Delete the build folder and the Xcode project"
	@echo "make clean-shared-cache  Delete the build cache that all folders share (waits for the builds that use it)"
	@echo "make docs-screenshots    Take the app screenshots of the docs on the shared Simulator (takes the Simulator lock)"
	@echo "make live-activity-render  Draw the Live Activity views for every station and page, in French, and list the too tall ones, the cut texts and the breaches of the cut rules (takes the Simulator lock; not in the gate)"
	@echo "make live-activity-render ENGLISH=1  Same, in French, then in English"

setup:
	@command -v xcodegen > /dev/null || brew install xcodegen
	@command -v swiftlint > /dev/null || brew install swiftlint
	@command -v pngquant > /dev/null || brew install pngquant
	@$(MAKE) generate

generate:
	@$(REMOVE_OLD_PROJECT)
	xcodegen generate --quiet --cache-path $(XCODEGEN_CACHE)
	@./scripts/bundle-id-check.sh --local --show $(PROJECT)

project:
	@$(REMOVE_OLD_PROJECT)
	@xcodegen generate --use-cache --quiet --cache-path $(XCODEGEN_CACHE)
	@./scripts/bundle-id-check.sh --local $(PROJECT)

git-hooks:
	@./scripts/git-hooks.sh on

git-hooks-off:
	@./scripts/git-hooks.sh off

lint:
	swiftlint lint --strict --quiet

lint-fix:
	swiftlint --fix --quiet
	swiftlint lint --strict --quiet

build: project
ifeq ($(LIVE),1)
	@test -f "$(PRIM_SECRETS)" || { echo "No PRIM key: $(PRIM_SECRETS) does not exist. Add the key there (see ios/README.md), or build without LIVE=1." >&2; exit 1; }
	@echo "LIVE=1: the build uses the PRIM key of $(PRIM_SECRETS)"
	@if [ "$(PRIM_SECRETS)" = "$(OLD_PRIM_SECRETS)" ]; then echo "Note: the key is at its old place. Once the main folder has the ios/ folder, move it there: cd $(MAIN_FOLDER) && mv Config/Secrets.xcconfig ios/Config/ && rmdir Config"; fi
	@$(BUILD_APP) -xcconfig "$(PRIM_SECRETS)" PRIM_SECRETS_STAMP="$$(stat -f '%Fm-%i-%z' "$(PRIM_SECRETS)")"
else
	@rm -rf $(BUILD_RESULT)
	$(BUILD_APP) $(NO_KEY) -resultBundlePath $(BUILD_RESULT)
	@xcrun xcresulttool get build-results --path $(BUILD_RESULT) | ./scripts/build-warnings.py
endif

strings-check: project
	@./scripts/strings-sync.sh check $(EXPORT_STRINGS)
	@./scripts/strings-check.py $(STRING_CATALOGS)
	@./scripts/app-name-sync.py --check Config/Base.xcconfig App/InfoPlist.xcstrings

strings-sync: project
	@./scripts/app-name-sync.py Config/Base.xcconfig App/InfoPlist.xcstrings
	@./scripts/strings-sync.sh sync $(EXPORT_STRINGS)

prose-check:
	@./scripts/prose-check.py

public-text-check:
	@./scripts/public-text-check.py

test:
	swift test --quiet --package-path $(CORE_PACKAGE) --scratch-path $(BUILD_DIR)/TROMECore -Xswiftc -warnings-as-errors

test-scripts:
	@mkdir -p $(BUILD_DIR)
	@for test in ./scripts/tests/*-test.sh; do \
		$$test > $(BUILD_DIR)/test-scripts.log 2>&1 || { cat $(BUILD_DIR)/test-scripts.log; exit 1; }; \
	done

check: lint prose-check public-text-check bundle-id-check recommended-settings-check live-key-check build strings-check test test-scripts

bundle-id-check: project
	@./scripts/bundle-id-check.sh $(PROJECT)

recommended-settings-check:
	@./scripts/recommended-settings-check.sh project.yml "$$(xcodebuild -version | head -1)"

live-key-check: project
	@RATP_SHARED_CACHE="$(RATP_SHARED_CACHE)" ./scripts/live-key-check.sh

run: build
	@$(SIM_LOCK) open $(SIMULATOR) launch "$(APP_PATH)"

switch-language:
	@$(SIM_LOCK) reopen $(SIMULATOR) switch-language "$(APP_PATH)"

e2e: project
	@for test in $(ONLY); do \
		class=$${test%%/*}; \
		files=$$(grep -lw "class $$class: E2ETestCase" UITests/*.swift) \
			|| { echo "No E2E test class named $$class in ios/UITests/" >&2; exit 1; }; \
		case $$test in */*) grep -qw "func $${test#*/}" $$files \
			|| { echo "No E2E test named $${test#*/} in $$class" >&2; exit 1; };; esac; \
	done
	@rm -rf $(E2E_RESULT)
	$(XCODEBUILD) $(NO_KEY) -scheme $(E2E_SCHEME) -destination 'generic/platform=iOS Simulator' ARCHS=$(HOST_ARCH) build-for-testing
	$(SIM_LOCK) job $(SIMULATOR) reset $(SIMULATOR) wait-for-widget-host $(SIMULATOR) grant-location "$(APP_PATH)" \
		$(SIMULATOR) with-destination $(XCODEBUILD) $(NO_KEY) -scheme $(E2E_SCHEME) \
		-parallel-testing-enabled NO -collect-test-diagnostics never \
		-test-timeouts-enabled YES -default-test-execution-time-allowance 300 \
		$(E2E_ONLY) -resultBundlePath $(E2E_RESULT) test-without-building \
		|| { status=$$?; ./scripts/e2e-failures.py $(E2E_RESULT); exit $$status; }

stations:
	python3 scripts/update-stations.py

simulator:
	@$(SIM_LOCK) udid

simulator-shutdown:
	@$(SIM_LOCK) free

simulator-delete:
	@$(SIM_LOCK) all $(SIMULATOR) delete

simulator-delete-old:
	@$(SIM_LOCK) job $(SIMULATOR) delete-old

clean:
	rm -rf $(BUILD_DIR) $(PROJECT) $(OLD_PROJECT)

clean-shared-cache:
	@./scripts/shared-cache.sh clear "$(RATP_SHARED_CACHE)"

merge:
	@./scripts/merge.sh

live-activity-render: project
	$(XCODEBUILD) $(NO_KEY) -scheme $(RENDER_SCHEME) -destination 'generic/platform=iOS Simulator' ARCHS=$(HOST_ARCH) build-for-testing
	$(SIM_LOCK) job $(SIMULATOR) reset $(SIMULATOR) with-destination \
		./scripts/live-activity-render.sh render $(RENDER_OUT) \
		$(XCODEBUILD) $(NO_KEY) -scheme $(RENDER_SCHEME) -collect-test-diagnostics never test-without-building
	./scripts/live-activity-render.sh report $(RENDER_OUT)

docs-screenshots: project
	$(XCODEBUILD) $(NO_KEY) -scheme $(DOCS_SCHEME) -destination 'generic/platform=iOS Simulator' ARCHS=$(HOST_ARCH) build-for-testing
	$(SIM_LOCK) job $(SIMULATOR) reset $(SIMULATOR) wait-for-widget-host $(SIMULATOR) with-destination \
		./scripts/docs-screenshots.sh $(DOCS_SCREENSHOTS_RESULT) \
		$(XCODEBUILD) $(NO_KEY) -scheme $(DOCS_SCHEME) \
		-parallel-testing-enabled NO -collect-test-diagnostics never \
		-test-timeouts-enabled YES -default-test-execution-time-allowance 300
