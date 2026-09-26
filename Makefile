PROJECT := RATPActivity.xcodeproj
APP_SCHEME := RATPActivity
E2E_SCHEME := RATPActivityE2E
BUILD_DIR := .build
DERIVED_DATA := $(BUILD_DIR)/DerivedData
APP_PATH := $(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/RATPActivity.app
SIMULATOR := ./scripts/simulator.sh
SIM_LOCK := ./scripts/sim-lock.sh
CORE_PACKAGE := Packages/RATPCore

XCODEBUILD := xcodebuild -quiet \
	-project $(PROJECT) \
	-derivedDataPath $(DERIVED_DATA) \
	-clonedSourcePackagesDirPath $(BUILD_DIR)/SourcePackages

.PHONY: help setup generate project lint lint-fix build test check run e2e stations simulator simulator-shutdown simulator-delete clean

help:
	@echo "make setup               Install the tools and create the Xcode project"
	@echo "make generate            Create the Xcode project again (after a change in project.yml)"
	@echo "make run                 Build the app and open it in this folder's Simulator (keeps the Simulator lock)"
	@echo "make check               Quality gate: lint + build + unit tests"
	@echo "make test                Unit tests only (on the Mac, no Simulator)"
	@echo "make e2e                 End-to-end tests on this folder's Simulator (takes the Simulator lock)"
	@echo "make lint-fix            Fix the lint problems that can be fixed automatically"
	@echo "make stations            Download the metro and RER station list again"
	@echo "make simulator           Print the ID of this folder's Simulator (creates it if needed)"
	@echo "make simulator-shutdown  Shut down this folder's Simulator and free the Simulator lock"
	@echo "make simulator-delete    Delete this folder's Simulator and free the Simulator lock"
	@echo "make clean               Delete the build folder and the Xcode project"

setup:
	@command -v xcodegen > /dev/null || brew install xcodegen
	@command -v swiftlint > /dev/null || brew install swiftlint
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
	$(XCODEBUILD) -scheme $(APP_SCHEME) -destination 'generic/platform=iOS Simulator' build

test:
	swift test --quiet --package-path $(CORE_PACKAGE) --scratch-path $(BUILD_DIR)/RATPCore

check: lint build test

run: build
	@$(SIM_LOCK) open $(SIMULATOR) launch "$(APP_PATH)"

e2e: project
	$(SIM_LOCK) job $(XCODEBUILD) -scheme $(E2E_SCHEME) -destination "id=$$($(SIMULATOR) udid)" \
		-parallel-testing-enabled NO -collect-test-diagnostics never \
		-test-timeouts-enabled YES -default-test-execution-time-allowance 300 test

stations:
	python3 scripts/update-stations.py

simulator:
	@$(SIMULATOR) udid

simulator-shutdown:
	@$(SIM_LOCK) free

simulator-delete:
	@$(SIM_LOCK) free
	@$(SIMULATOR) delete

clean:
	rm -rf $(BUILD_DIR) $(PROJECT)
