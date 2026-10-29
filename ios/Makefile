PROJECT := TROME.xcodeproj
OLD_PROJECT := RATPActivity.xcodeproj
APP_SCHEME := TROME
E2E_SCHEME := TROMEUITests
BUILD_DIR := .build
DERIVED_DATA := $(BUILD_DIR)/DerivedData
APP_NAME := $(shell sed -n -E 's/^APP_NAME = (.+)$$/\1/p' Config/Base.xcconfig)
APP_CONFIGURATION := $(if $(filter 1,$(RELEASE)),Release,Debug)
APP_PATH := $(DERIVED_DATA)/Build/Products/$(APP_CONFIGURATION)-iphonesimulator/$(APP_NAME).app
E2E_RESULT := $(BUILD_DIR)/e2e.xcresult
XCODEGEN_CACHE := $(BUILD_DIR)/xcodegen-cache
E2E_TARGET := TROMEUITests
E2E_ONLY := $(foreach test,$(ONLY),-only-testing:$(E2E_TARGET)/$(test))
DOCS_SCHEME := TROMEDocsScreenshots
DOCS_SCREENSHOTS_RESULT := $(BUILD_DIR)/docs-screenshots.xcresult
WALLPAPER_RESULT := $(BUILD_DIR)/simulator-wallpaper.xcresult
STORE_SCREENSHOTS_RESULT := $(BUILD_DIR)/store-screenshots.xcresult
STORE_COMPOSER := $(BUILD_DIR)/store-screenshots-compose
# The composer places the line badge by the rule of the app's badge, so it builds with that file of the app.
STORE_COMPOSER_SOURCES := scripts/store-screenshots-compose/main.swift Packages/TROMECore/Sources/TROMEBadge/LineBadge/LabelInk.swift
RENDER_SCHEME := TROMERenderCheck
RENDER_OUT := $(BUILD_DIR)/live-activity-render
BUILD_RESULT := $(BUILD_DIR)/build.xcresult
RELEASE_ARCHIVE_DIR := $(BUILD_DIR)/release-archive-check
RELEASE_ARCHIVE := $(RELEASE_ARCHIVE_DIR)/$(APP_NAME).xcarchive
RELEASE_ARCHIVE_RESULT := $(RELEASE_ARCHIVE_DIR)/archive.xcresult
SIMULATOR := ./scripts/simulator.sh
SIM_LOCK := ./scripts/sim-lock.sh
# What the record of a 'make run' says besides its kind (sim-lock.sh, make simulator-times).
RUN_DETAIL := $(strip $(if $(filter 1,$(LIVE)),LIVE=1) $(if $(filter 1,$(RELEASE)),RELEASE=1) $(if $(filter 1,$(SMALL)),SMALL=1) $(if $(LANGUAGE),LANGUAGE=$(LANGUAGE)))
QUIET := ./scripts/quiet.sh
BUILD_GATE := ./scripts/build-gate.py build
TEST_RUN_GATE := ./scripts/build-gate.py tests
LOGS := $(BUILD_DIR)/logs
CORE_PACKAGE := Packages/TROMECore
NO_KEY := -xcconfig Config/NoKey.xcconfig
# make build (so make check and make run) compiles the silent start, which only Debug builds of a paid team turn on,
# so that no check leaves its code uncompiled; NoKey.xcconfig gives it no server, so it stays off at run time.
# The E2E builds compile the app without it.
SILENT_START_COMPILED := TROME_SILENT_START=YES
MAIN_FOLDER = $(shell git worktree list --porcelain | sed -n '1s/^worktree //p')
OLD_PRIM_SECRETS = $(MAIN_FOLDER)/Config/Secrets.xcconfig
PRIM_SECRETS ?= $(firstword $(wildcard $(MAIN_FOLDER)/ios/Config/Secrets.xcconfig $(OLD_PRIM_SECRETS)) $(MAIN_FOLDER)/ios/Config/Secrets.xcconfig)
TROME_SHARED_CACHE ?= $(HOME)/Library/Caches/TROME
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

# RELEASE=1: the app as the store ships it (Release configuration: no Testing tools, no PRIM key), for the Simulator.
# Config/ReleaseRun.xcconfig gives it a server host that never answers, so it shows no real trains.
ifeq ($(RELEASE),1)
ifneq ($(filter-out build run switch-language,$(MAKECMDGOALS)),)
$(error RELEASE=1 works only with 'make build', 'make run' and 'make switch-language')
endif
ifeq ($(LIVE),1)
$(error RELEASE=1 never holds the PRIM key: use LIVE=1 or RELEASE=1, not both)
endif
endif

ifeq ($(LIVE),1)
ifneq ($(filter-out build run,$(MAKECMDGOALS)),)
$(error LIVE=1 works only with 'make build' and 'make run')
endif
USE_SHARED_CACHE :=
SHARED_SDK_MODULES :=
else
USE_SHARED_CACHE := ./scripts/shared-cache.sh use "$(TROME_SHARED_CACHE)"
SHARED_SDK_MODULES := SDK_EXPLICIT_MODULES_OUTPUT_PATH="$(TROME_SHARED_CACHE)/SDKExplicitPrecompiledModules"
endif

XCODEBUILD := $(BUILD_GATE) $(USE_SHARED_CACHE) xcodebuild -quiet \
	-project $(PROJECT) \
	-derivedDataPath $(DERIVED_DATA) \
	-clonedSourcePackagesDirPath $(BUILD_DIR)/SourcePackages \
	COMPILER_INDEX_STORE_ENABLE=NO $(SHARED_SDK_MODULES) \
	SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES
BUILD_APP := $(XCODEBUILD) -scheme $(APP_SCHEME) -destination 'generic/platform=iOS Simulator' ARCHS=$(HOST_ARCH) build
# The Release build is not signed: the store build is signed by the paid team, and the Simulator runs it unsigned.
BUILD_RELEASE_APP := $(XCODEBUILD) -scheme $(APP_SCHEME) -configuration Release -destination 'generic/platform=iOS Simulator' ARCHS=$(HOST_ARCH) \
	CODE_SIGNING_ALLOWED=NO -xcconfig Config/ReleaseRun.xcconfig build
EXPORT_STRINGS := $(XCODEBUILD) $(NO_KEY) -scheme $(APP_SCHEME) CODE_SIGNING_ALLOWED=NO \
	-exportLocalizations -localizationPath $(BUILD_DIR)/Localizations -exportLanguage fr
STRING_CATALOGS = $(wildcard App/*.xcstrings Widget/*.xcstrings)
REMOVE_OLD_PROJECT := if [ -e $(OLD_PROJECT) ]; then rm -rf $(OLD_PROJECT) && echo "Removed the old Xcode project ios/$(OLD_PROJECT): open ios/$(PROJECT) instead"; fi

.PHONY: help setup generate project git-hooks git-hooks-off lint lint-fix build strings-check strings-sync prose-check public-text-check bundle-id-check release-signing-check release-server-check release-server-timing release-tokens-check release-archive-check app-icon-check test test-scripts check live-key-check recommended-settings-check run switch-language fake-trains e2e stations simulator simulator-shutdown simulator-times simulator-delete simulator-delete-old simulator-wallpaper simulator-wallpaper-set clean clean-shared-cache docs-screenshots store-screenshots store-screenshots-compose live-activity-render merge

help:
	@echo "make setup               Install the tools and create the Xcode project"
	@echo "make generate            Create the Xcode project again (after a change in project.yml or ios/Config), and refuse the App Store IDs in the Debug IDs of ios/Config"
	@echo "make git-hooks           Turn on the git hooks: after a git pull or a checkout in the main folder, the Xcode project is created again"
	@echo "make git-hooks-off       Turn off the git hooks"
	@echo "make build               Build the app for the Simulator, with no warning allowed (make run builds it first)"
	@echo "make run                 Build the app and open it in the shared Simulator (keeps the Simulator lock)"
	@echo "make run LIVE=1          Same, with your PRIM key from the main folder of the repo (ios/Config/Secrets.xcconfig, see ios/README.md)"
	@echo "make run SMALL=1         Same, on the smallest supported iPhone (an iPhone SE, 375 x 667 pt; keeps the Simulator lock)"
	@echo "make run LANGUAGE=fr     Same, with the Simulator in French (the default is English: LANGUAGE=en)"
	@echo "make run RELEASE=1       Same, with the app as the store ships it: Release configuration, no Testing tools, no PRIM key, and a server that never answers, so no real trains (also for make build and make switch-language)"
	@echo "make switch-language LANGUAGE=en  After make run: put the Simulator in this language (en or fr) and open the app again, with its data"
	@echo "make fake-trains STATE=at-platform  After make run: open the app again with fake trains in this state (no STATE: the default times), and say whether the app uses them"
	@echo "make check               iOS quality gate: lint + Markdown line check + public text check + bundle ID check + app icon check + recommended settings check + key leak check (with the upload checks of the Release app) + build (no warning allowed) + strings check + unit tests + script tests"
	@echo "make strings-check       Fail when a build in Xcode would change a String Catalog, when a text of the app or the Live Activity has no French text, or when a French permission text does not say APP_NAME"
	@echo "make strings-sync        Update the String Catalogs as a build in Xcode does (new texts, texts no longer in the code), and put APP_NAME of Config/Base.xcconfig in the permission texts"
	@echo "make prose-check         Fail when a line of prose of a Markdown or MDX file of the repo is longer than 400 characters (write one sentence per line)"
	@echo "make public-text-check   Fail when a file of the repo has a backlog id, a word of the team's own process, a personal email address, a local path, the old name of the app, or \"we\" in the prose"
	@echo "make test                Unit tests only (on the Mac, no Simulator)"
	@echo "make test-scripts        Tests of the scripts: the Simulator lock (with a fake xcrun, no Simulator) and the warning checks"
	@echo "make live-key-check      Prove that a LIVE=1 build does not print the key, that a new key replaces the old one, that a Release build holds the app token of the server but never the PRIM key, that a Release build with no server host or no app token fails, and that the Release app passes the upload checks of App Store Connect: an icon of 1024 x 1024 pixels with no transparent pixel, a privacy manifest with a reason for each required reason API that its code uses, the answer on encryption, a version such as 1.0.0, no placeholder address (uses fake values)"
	@echo "make app-icon-check      Fail when the app has no store icon of 1024 x 1024 pixels, or when its icon has an alpha channel"
	@echo "make bundle-id-check     Fail when a Debug build could carry the App Store bundle ID (also with the Debug IDs of Local.xcconfig set), or when a Release build is signed automatically with no TROME_RELEASE_TEAM"
	@echo "make release-signing-check  Fail when Xcode would sign a Release build with no TROME_RELEASE_TEAM, or would not sign it automatically with one (no compile, no Apple account)"
	@echo "make release-server-check  Before an archive: say in one line whether the production server accepts the host and the app token of ios/Config/Server.xcconfig (one request for the trains of one stop; prints neither)"
	@echo "make release-server-timing  Split the time of a call to the production server of ios/Config/Server.xcconfig: connection, Worker, server object, PRIM (5 calls of one rider in 35 s, at most 2 PRIM calls; prints neither)"
	@echo "make release-tokens-check  After every change of a secret of the production server, and before every upload: say, one line per build that riders may hold, whether the production server accepts its app token of ios/Config/BuildTokens.txt (one request per build; prints no token)"
	@echo "make release-archive-check  Build an unsigned Release archive of the app and its widget for an iPhone, with stand-in server values: shows that the store build compiles, with no account and no secret (not in make check)"
	@echo "make recommended-settings-check  Fail when the installed Xcode is newer than the one that last checked the project settings"
	@echo "make e2e                 End-to-end tests on the shared Simulator (takes the Simulator lock); a failed run keeps its log, its .xcresult and the Simulator log in ~/Library/Logs/TROME/e2e-failures/"
	@echo "make e2e ONLY=<TestClass>  Only these E2E test classes (or Class/testMethod), separated by spaces"
	@echo "make merge               Merge the branch of this folder into main (after QA), before the other Simulator jobs: rebase, make check, full make e2e, fast-forward. Merges that wait together share one run; when it fails, they land one by one"
	@echo "make lint-fix            Fix the lint problems that can be fixed automatically"
	@echo "make stations            Download the metro and RER station list again"
	@echo "make simulator           Print the ID of the Simulator of this folder after make run, else of RATP-Shared (creates it if needed)"
	@echo "make simulator-shutdown  Remove the app of 'make run' from the Simulator and free the lock (the Simulator shuts down when idle)"
	@echo "make simulator-times     How long the Simulator jobs waited for the Simulator and held it, by kind (merge, e2e, run...), and how long builds waited for a test run; SINCE=2026-10-08 for a part (records in ~/Library/Logs/TROME/)"
	@echo "make simulator-delete    Delete the shared Simulators, also those of a second-slot trial (waits until no other Simulator job runs)"
	@echo "make simulator-delete-old  Delete the old Simulators of each folder (takes the Simulator lock)"
	@echo "make simulator-wallpaper  Set the wallpaper of the pictures (ios/DocsScreenshots/Wallpaper.swift) on the shared Simulator, once: it keeps it (takes the Simulator lock; does nothing when it is already set)"
	@echo "make clean               Delete the build folder and the Xcode project"
	@echo "make clean-shared-cache  Delete the build cache that all folders share (waits for the builds that use it)"
	@echo "make docs-screenshots    Take the app screenshots of the docs on the shared Simulator (takes the Simulator lock); a failed run keeps its evidence, as make e2e does"
	@echo "make store-screenshots   Make the store pictures, in English and French, from captures of the shared Simulator (takes the Simulator lock), in ios/.build/store-screenshots/"
	@echo "make store-screenshots-compose  Make the store pictures again from the last captures, with no Simulator"
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
	@$(QUIET) $(LOGS)/lint.log '' swiftlint lint --strict --quiet

lint-fix:
	swiftlint --fix --quiet
	swiftlint lint --strict --quiet

# With LIVE=1, Xcode keeps its copy of the build settings (the build description, in .build/DerivedData) until the path
# of an -xcconfig file changes, not its content. So PRIM_SECRETS_STAMP passes the time, the file number and the size of
# the key file (never its content): a new key changes the stamp, and Xcode reads the file again.
build: project
ifeq ($(LIVE),1)
	@test -f "$(PRIM_SECRETS)" || { echo "No PRIM key: $(PRIM_SECRETS) does not exist. Add the key there (see ios/README.md), or build without LIVE=1." >&2; exit 1; }
	@echo "LIVE=1: the build uses the PRIM key of $(PRIM_SECRETS)"
	@if [ "$(PRIM_SECRETS)" = "$(OLD_PRIM_SECRETS)" ]; then echo "Note: the key is at its old place. Once the main folder has the ios/ folder, move it there: cd $(MAIN_FOLDER) && mv Config/Secrets.xcconfig ios/Config/ && rmdir Config"; fi
	@$(BUILD_APP) -xcconfig "$(PRIM_SECRETS)" PRIM_SECRETS_STAMP="$$(stat -f '%Fm-%i-%z' "$(PRIM_SECRETS)")"
else ifeq ($(RELEASE),1)
	@rm -rf $(BUILD_RESULT)
	@$(BUILD_GATE) $(QUIET) $(LOGS)/build-release.log '' $(BUILD_RELEASE_APP) -resultBundlePath $(BUILD_RESULT)
	@xcrun xcresulttool get build-results --path $(BUILD_RESULT) | ./scripts/build-warnings.py
else
	@rm -rf $(BUILD_RESULT)
	@$(BUILD_GATE) $(QUIET) $(LOGS)/build.log '' $(BUILD_APP) $(NO_KEY) $(SILENT_START_COMPILED) -resultBundlePath $(BUILD_RESULT)
	@xcrun xcresulttool get build-results --path $(BUILD_RESULT) | ./scripts/build-warnings.py
endif

strings-check: project
	@$(BUILD_GATE) ./scripts/strings-sync.sh check $(EXPORT_STRINGS)
	@./scripts/strings-check.py $(STRING_CATALOGS)
	@./scripts/app-name-sync.py --check Config/Base.xcconfig App/InfoPlist.xcstrings

strings-sync: project
	@./scripts/app-name-sync.py Config/Base.xcconfig App/InfoPlist.xcstrings
	@$(BUILD_GATE) ./scripts/strings-sync.sh sync $(EXPORT_STRINGS)

prose-check:
	@./scripts/prose-check.py

public-text-check:
	@./scripts/public-text-check.py

test:
	@$(BUILD_GATE) $(QUIET) $(LOGS)/unit-tests.log 'Test run with|Executed [1-9]' swift test --quiet --package-path $(CORE_PACKAGE) --scratch-path $(BUILD_DIR)/TROMECore -Xswiftc -warnings-as-errors

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

check: lint prose-check public-text-check bundle-id-check release-signing-check app-icon-check recommended-settings-check live-key-check build strings-check test test-scripts

bundle-id-check: project
	@./scripts/bundle-id-check.sh $(PROJECT)

# Not through the build gate: each build stops at the signing check, before any compile, in a few seconds.
release-signing-check: project
	@./scripts/release-signing-check.sh $(PROJECT) $(BUILD_DIR)/release-signing-check

# Not in make check: it calls the production server with the token of the maintainer's own file.
release-server-check:
	@./scripts/release-server-check.sh Config/Server.xcconfig

# Not in make check: it calls the production server with the token of the maintainer's own file.
release-server-timing:
	@./scripts/release-server-timing.sh Config/Server.xcconfig

# Not in make check: it calls the production server with the tokens of the maintainer's own file.
release-tokens-check:
	@./scripts/release-tokens-check.sh Config/BuildTokens.txt Config/Server.xcconfig ../docs/src/content/docs/en/maintain/release-on-the-app-store.mdx

# Not in make check: a Release build for an iPhone takes minutes. The release checks workflow on GitHub runs it.
# Unsigned, with the stand-in server values of Config/ReleaseRun.xcconfig: it never holds a real token, and it cannot ship.
release-archive-check: project
	@rm -rf $(RELEASE_ARCHIVE_DIR)
	@$(BUILD_GATE) $(QUIET) $(LOGS)/release-archive.log '' $(XCODEBUILD) -scheme $(APP_SCHEME) -configuration Release \
		-destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -xcconfig Config/ReleaseRun.xcconfig \
		-archivePath $(RELEASE_ARCHIVE) -resultBundlePath $(RELEASE_ARCHIVE_RESULT) archive
	@xcrun xcresulttool get build-results --path $(RELEASE_ARCHIVE_RESULT) | ./scripts/build-warnings.py
	@test -d "$(RELEASE_ARCHIVE)/Products/Applications/$(APP_NAME).app/PlugIns/$(APP_NAME)Widget.appex" \
		|| { echo "release-archive-check: FAILED: the archive has no $(APP_NAME).app with its widget $(APP_NAME)Widget.appex" >&2; exit 1; }
	@echo "release-archive-check: OK ($(APP_NAME).app with its widget, unsigned, in ios/$(RELEASE_ARCHIVE))"

app-icon-check:
	@./scripts/app-icon-check.py App/Assets.xcassets/AppIcon.appiconset

recommended-settings-check:
	@./scripts/recommended-settings-check.sh project.yml "$$(xcodebuild -version | head -1)"

live-key-check: project
	@TROME_SHARED_CACHE="$(TROME_SHARED_CACHE)" ./scripts/live-key-check.sh

run: build
	@RATP_SIM_KIND=run RATP_SIM_DETAIL="$(RUN_DETAIL)" $(SIM_LOCK) open $(SIMULATOR) launch "$(APP_PATH)"

switch-language:
	@$(SIM_LOCK) reopen $(SIMULATOR) switch-language "$(APP_PATH)"

fake-trains:
	@$(SIM_LOCK) reopen ./scripts/fake-trains.sh "$(APP_PATH)" $(STATE)

# The E2E tests collect no Simulator diagnostics on a failure: they took about 10 minutes, and kept the Simulator.
e2e: project
	@for test in $(ONLY); do \
		class=$${test%%/*}; \
		files=$$(grep -lw "class $$class: E2ETestCase" UITests/*.swift) \
			|| { echo "No E2E test class named $$class in ios/UITests/" >&2; exit 1; }; \
		case $$test in */*) grep -qw "func $${test#*/}" $$files \
			|| { echo "No E2E test named $${test#*/} in $$class" >&2; exit 1; };; esac; \
	done
	@rm -rf $(E2E_RESULT)
	@$(BUILD_GATE) $(QUIET) $(LOGS)/e2e-build.log '' $(XCODEBUILD) $(NO_KEY) -scheme $(E2E_SCHEME) -destination 'generic/platform=iOS Simulator' ARCHS=$(HOST_ARCH) build-for-testing
	@RATP_SIM_KIND=e2e RATP_SIM_DETAIL="$(ONLY)" $(SIM_LOCK) job $(TEST_RUN_GATE) $(SIMULATOR) reset $(SIMULATOR) wait-for-wallpaper-update $(SIMULATOR) wait-for-widget-host $(SIMULATOR) grant-location "$(APP_PATH)" \
		$(SIMULATOR) with-destination $(QUIET) $(LOGS)/e2e.log '^E2E tests: ' \
		sh -c './scripts/mac-load-log.sh $(LOGS)/mac-load.log & load_log=$$!; "$$@"; status=$$?; kill $$load_log 2>/dev/null; ./scripts/e2e-failures.py $(E2E_RESULT); [ $$status -eq 0 ] || ./scripts/e2e-keep.py $(E2E_RESULT) $(LOGS)/e2e.log "$(APP_PATH)"; exit $$status' e2e \
		$(XCODEBUILD) $(NO_KEY) -scheme $(E2E_SCHEME) \
		-parallel-testing-enabled NO -collect-test-diagnostics never \
		-test-timeouts-enabled YES -default-test-execution-time-allowance 300 \
		$(E2E_ONLY) -resultBundlePath $(E2E_RESULT) test-without-building

stations:
	python3 scripts/update-stations.py

simulator:
	@$(SIM_LOCK) udid

simulator-shutdown:
	@$(SIM_LOCK) free

simulator-times:
	@./scripts/simulator-times.py $(if $(SINCE),--since "$(SINCE)")

simulator-delete:
	@RATP_SIM_KIND=simulator-delete $(SIM_LOCK) all $(SIMULATOR) delete

simulator-delete-old:
	@RATP_SIM_KIND=simulator-delete-old $(SIM_LOCK) job $(SIMULATOR) delete-old

clean:
	rm -rf $(BUILD_DIR) $(PROJECT) $(OLD_PROJECT)

clean-shared-cache:
	@./scripts/shared-cache.sh clear "$(TROME_SHARED_CACHE)"

merge:
	@./scripts/merge.sh

store-screenshots: project
	@./scripts/wallpaper.sh check
	@$(BUILD_GATE) $(QUIET) $(LOGS)/store-screenshots-build.log '' $(XCODEBUILD) $(NO_KEY) -scheme $(DOCS_SCHEME) -destination 'generic/platform=iOS Simulator' ARCHS=$(HOST_ARCH) build-for-testing
	@RATP_SIM_KIND=store-screenshots $(SIM_LOCK) job $(TEST_RUN_GATE) $(SIMULATOR) reset $(SIMULATOR) wait-for-wallpaper-update $(SIMULATOR) wait-for-widget-host $(SIMULATOR) with-destination \
		$(QUIET) $(LOGS)/store-screenshots.log '^Captured ' ./scripts/store-screenshots.sh capture $(STORE_SCREENSHOTS_RESULT) $(LOGS)/store-screenshots.log "$(APP_PATH)" \
		$(XCODEBUILD) $(NO_KEY) -scheme $(DOCS_SCHEME) \
		-parallel-testing-enabled NO -collect-test-diagnostics never \
		-test-timeouts-enabled YES -default-test-execution-time-allowance 300
	@$(MAKE) --no-print-directory store-screenshots-compose

store-screenshots-compose:
	@mkdir -p $(LOGS)
	@$(BUILD_GATE) $(QUIET) $(LOGS)/store-screenshots-composer-build.log '' swiftc -O $(STORE_COMPOSER_SOURCES) -o $(STORE_COMPOSER)
	@./scripts/store-screenshots.sh compose $(STORE_COMPOSER)

live-activity-render: project
	@$(BUILD_GATE) $(QUIET) $(LOGS)/live-activity-render-build.log '' $(XCODEBUILD) $(NO_KEY) -scheme $(RENDER_SCHEME) -destination 'generic/platform=iOS Simulator' ARCHS=$(HOST_ARCH) build-for-testing
	@RATP_SIM_KIND=live-activity-render $(SIM_LOCK) job $(TEST_RUN_GATE) $(SIMULATOR) reset $(SIMULATOR) with-destination \
		$(QUIET) $(LOGS)/live-activity-render.log '^Simulator time' ./scripts/live-activity-render.sh render $(RENDER_OUT) \
		$(XCODEBUILD) $(NO_KEY) -scheme $(RENDER_SCHEME) -collect-test-diagnostics never test-without-building
	@$(BUILD_GATE) ./scripts/live-activity-render.sh report $(RENDER_OUT)

simulator-wallpaper: project
	@if ./scripts/wallpaper.sh check 2> /dev/null; then echo "Wallpaper $$(./scripts/wallpaper.sh id): already set, nothing to do"; \
		else $(MAKE) --no-print-directory simulator-wallpaper-set; fi

# Only through make simulator-wallpaper, when the check fails.
simulator-wallpaper-set:
	@$(BUILD_GATE) $(QUIET) $(LOGS)/simulator-wallpaper-build.log '' $(XCODEBUILD) $(NO_KEY) -scheme $(DOCS_SCHEME) -destination 'generic/platform=iOS Simulator' ARCHS=$(HOST_ARCH) build-for-testing
	@RATP_SIM_KIND=simulator-wallpaper $(SIM_LOCK) job $(TEST_RUN_GATE) $(SIMULATOR) reset $(SIMULATOR) with-destination \
		$(QUIET) $(LOGS)/simulator-wallpaper.log '^Wallpaper ' ./scripts/wallpaper.sh set $(WALLPAPER_RESULT) \
		$(XCODEBUILD) $(NO_KEY) -scheme $(DOCS_SCHEME) -parallel-testing-enabled NO -collect-test-diagnostics never

docs-screenshots: project
	@./scripts/wallpaper.sh check
	@$(BUILD_GATE) $(QUIET) $(LOGS)/docs-screenshots-build.log '' $(XCODEBUILD) $(NO_KEY) -scheme $(DOCS_SCHEME) -destination 'generic/platform=iOS Simulator' ARCHS=$(HOST_ARCH) build-for-testing
	@RATP_SIM_KIND=docs-screenshots $(SIM_LOCK) job $(TEST_RUN_GATE) $(SIMULATOR) reset $(SIMULATOR) wait-for-wallpaper-update $(SIMULATOR) wait-for-widget-host $(SIMULATOR) with-destination \
		$(QUIET) $(LOGS)/docs-screenshots.log '^Saved ' ./scripts/docs-screenshots.sh $(DOCS_SCREENSHOTS_RESULT) $(LOGS)/docs-screenshots.log "$(APP_PATH)" \
		$(XCODEBUILD) $(NO_KEY) -scheme $(DOCS_SCHEME) \
		-parallel-testing-enabled NO -collect-test-diagnostics never \
		-test-timeouts-enabled YES -default-test-execution-time-allowance 300
