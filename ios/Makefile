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
RELEASE_RUN_SCHEME := TROMEReleaseRun
RELEASE_RUN_RESULT := $(BUILD_DIR)/release-run.xcresult
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
# make build (so make check and make run) compiles the silent start, which every Release build and the Debug builds
# of a paid team turn on, so that no check leaves its code uncompiled; NoKey.xcconfig gives it no server, so it stays
# off at run time.
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
RELEASE_RUN_SETTINGS := -configuration Release CODE_SIGNING_ALLOWED=NO -xcconfig Config/ReleaseRun.xcconfig
BUILD_RELEASE_APP := $(XCODEBUILD) -scheme $(APP_SCHEME) $(RELEASE_RUN_SETTINGS) -destination 'generic/platform=iOS Simulator' ARCHS=$(HOST_ARCH) build
EXPORT_STRINGS := $(XCODEBUILD) $(NO_KEY) -scheme $(APP_SCHEME) CODE_SIGNING_ALLOWED=NO \
	-exportLocalizations -localizationPath $(BUILD_DIR)/Localizations -exportLanguage fr
STRING_CATALOGS = $(wildcard App/*.xcstrings Widget/*.xcstrings)
REMOVE_OLD_PROJECT := if [ -e $(OLD_PROJECT) ]; then rm -rf $(OLD_PROJECT) && echo "Removed the old Xcode project ios/$(OLD_PROJECT): open ios/$(PROJECT) instead"; fi

.PHONY: help setup generate project git-hooks git-hooks-off lint-fix strings-sync release-notes release-server-check release-server-timing release-tokens-check phone-set-record release-archive-check check run switch-language fake-trains e2e stations simulator simulator-shutdown simulator-times simulator-delete simulator-delete-old simulator-wallpaper simulator-wallpaper-set clean clean-shared-cache docs-screenshots store-screenshots store-screenshots-compose live-activity-render release-run-check merge e2e-proof

help::
	@echo "make setup               Install the tools and create the Xcode project"
	@echo "make generate            Create the Xcode project again (after a change in project.yml or ios/Config), and refuse the App Store IDs in the Debug IDs of ios/Config"
	@echo "make git-hooks           Turn on the git hooks: after a git pull or a checkout in the main folder, the Xcode project is created again"
	@echo "make git-hooks-off       Turn off the git hooks"
	@echo "make run                 Build the app and open it in the shared Simulator (keeps the Simulator lock)"
	@echo "make run LIVE=1          Same, with your PRIM key from the main folder of the repo (ios/Config/Secrets.xcconfig, see ios/README.md)"
	@echo "make run SMALL=1         Same, on the smallest supported iPhone (an iPhone SE, 375 x 667 pt; keeps the Simulator lock)"
	@echo "make run LANGUAGE=fr     Same, with the Simulator in French (the default is English: LANGUAGE=en)"
	@echo "make run RELEASE=1       Same, with the app as the store ships it: Release configuration, no Testing tools, no PRIM key, and a server that never answers, so no real trains (also for make build and make switch-language)"
	@echo "make switch-language LANGUAGE=en  After make run: put the Simulator in this language (en or fr) and open the app again, with its data"
	@echo "make fake-trains STATE=at-platform  After make run: open the app again with fake trains in this state (no STATE: the default times), and say whether the app uses them"
	@echo "make check               iOS quality gate: $(CHECK_STEPS)"

# The checks of make check: one file each in checks/, with its rule and its help line; make check runs them in the
# order of the file names. So a new check is a new file, and two tasks that each add a check change no same line.
include $(sort $(wildcard checks/*.mk))
CHECK_STEPS_JOINED = $(foreach check,$(CHECKS),+ $(CHECK_STEP_$(check)))
CHECK_STEPS = $(wordlist 2,$(words $(CHECK_STEPS_JOINED)),$(CHECK_STEPS_JOINED))
check: $(CHECKS)

help::
	@echo "make strings-sync        Update the String Catalogs as a build in Xcode does (new texts, texts no longer in the code), and put APP_NAME of Config/Base.xcconfig in the permission texts"
	@echo "make release-server-check  Before an archive: say in one line whether the production server accepts the host and the app token of ios/Config/Server.xcconfig (one request for the trains of one stop; prints neither)"
	@echo "make release-server-timing  Split the time of a call to the production server of ios/Config/Server.xcconfig: connection, Worker, server object, PRIM (5 calls of one rider in 35 s, at most 2 PRIM calls; prints neither)"
	@echo "make release-notes       Print the What's New of the next store release and the TestFlight What to Test, in French and English, from the notes of ios/changes/ that the build on the App Store does not hold; or no release, with the lines that wait (fails on two headlines)"
	@echo "make phone-set-record BUILD=<version>-<build>  At each upload, from the commit of the build: record in contracts/phone/ the values that it keeps on the phone, which make test reads with the code of today"
	@echo "make release-tokens-check  After every change of a secret of the production server, and before every upload: say, one line per build that riders may hold, whether the production server accepts its app token of ios/Config/BuildTokens.txt (one request per build; prints no token)"
	@echo "make release-archive-check  Build an unsigned Release archive of the app and its widget for an iPhone, with stand-in server values: shows that the store build compiles, with the silent start, its push capability and its app group, with no account and no secret (not in make check)"
	@echo "make e2e                 End-to-end tests on the shared Simulator (takes the Simulator lock); a failed run keeps its log, its .xcresult and the Simulator log in ~/Library/Logs/TROME/e2e-failures/"
	@echo "make e2e ONLY=<TestClass>  Only these E2E test classes (or Class/testMethod), separated by spaces"
	@echo "make release-run-check   Start the app as the store ships it (as make run RELEASE=1 builds it) on the shared Simulator, and fail when it does not reach its first screen or shows a Testing tool (takes the Simulator lock; make merge runs it)"
	@echo "make merge               Merge the branch of this folder into main (after QA), before the other Simulator jobs: rebase, make check, full make e2e, make release-run-check, fast-forward, then push main with the record of both passes and its render counts. Merges that wait together share one run; when it fails, they land one by one"
	@echo "make e2e-proof           Say whether a commit (COMMIT=, default HEAD) has, on GitHub, the record that make merge leaves after a full E2E pass and a run of the Release app on its tree, and its render counts; fail when either is missing (the release refuses it)"
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

lint-fix:
	swiftlint --fix --quiet
	swiftlint lint --strict --quiet

strings-sync: project
	@./scripts/app-name-sync.py Config/Base.xcconfig App/InfoPlist.xcstrings
	@$(BUILD_GATE) ./scripts/strings-sync.sh sync $(EXPORT_STRINGS)

# Not in make check: it calls the production server with the token of the maintainer's own file.
release-server-check:
	@./scripts/release-server-check.sh Config/Server.xcconfig

# Not in make check: it calls the production server with the token of the maintainer's own file.
release-server-timing:
	@./scripts/release-server-timing.sh Config/Server.xcconfig

release-notes:
	@./scripts/release-notes.py

# At each upload: the build of tag builds/<version>/<build> records what it keeps on the phone, from its own code.
phone-set-record: PHONE_SET_TAG = builds/$(subst -,/,$(BUILD))
phone-set-record: PHONE_SET_OUT = $(abspath $(CURDIR)/../contracts/phone/$(BUILD))
phone-set-record:
	@[ -n "$(BUILD)" ] || { echo "phone-set-record: name the build, for example BUILD=1.0.0-4"; exit 1; }
	@git rev-parse -q --verify "$(PHONE_SET_TAG)^{commit}" > /dev/null || { echo "phone-set-record: no tag $(PHONE_SET_TAG): tag the build first"; exit 1; }
	@git diff --quiet "$(PHONE_SET_TAG)" -- $(CORE_PACKAGE) || { echo "phone-set-record: $(CORE_PACKAGE) is not the code of $(PHONE_SET_TAG): record from the commit of the build"; exit 1; }
	@[ ! -e "$(PHONE_SET_OUT)" ] || { echo "phone-set-record: contracts/phone/$(BUILD) exists, and a recorded set is never written again"; exit 1; }
	@$(BUILD_GATE) env PHONE_SET_RECORD="$(PHONE_SET_OUT)" swift test --quiet --package-path $(CORE_PACKAGE) --scratch-path $(BUILD_DIR)/TROMECore -Xswiftc -warnings-as-errors --filter PhoneSetRecorder
	@echo "phone-set-record: wrote contracts/phone/$(BUILD)/: commit it"

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
	@./scripts/release-entitlements-check.py $(PROJECT) $(RELEASE_ARCHIVE)
	@echo "release-archive-check: OK ($(APP_NAME).app with its widget, unsigned, in ios/$(RELEASE_ARCHIVE))"

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

# The app as the store ships it, started by iOS: the test of ios/ReleaseRun/ needs no wallpaper, widget host or permission.
release-run-check: project
	@rm -rf $(RELEASE_RUN_RESULT)
	@$(BUILD_GATE) $(QUIET) $(LOGS)/release-run-build.log '' $(XCODEBUILD) -scheme $(RELEASE_RUN_SCHEME) $(RELEASE_RUN_SETTINGS) -destination 'generic/platform=iOS Simulator' ARCHS=$(HOST_ARCH) build-for-testing
	@RATP_SIM_KIND=release-run $(SIM_LOCK) job $(TEST_RUN_GATE) $(SIMULATOR) reset $(SIMULATOR) with-destination \
		$(QUIET) $(LOGS)/release-run.log '^E2E tests: ' \
		sh -c '"$$@"; status=$$?; ./scripts/e2e-failures.py $(RELEASE_RUN_RESULT); exit $$status' release-run \
		$(XCODEBUILD) -scheme $(RELEASE_RUN_SCHEME) $(RELEASE_RUN_SETTINGS) -collect-test-diagnostics never \
		-test-timeouts-enabled YES -default-test-execution-time-allowance 300 -resultBundlePath $(RELEASE_RUN_RESULT) test-without-building
	@echo "release-run-check: OK (the Release app reached its first screen, with no Testing tools)"

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

e2e-proof:
	@./scripts/e2e-proof.sh read $(or $(COMMIT),HEAD)

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
