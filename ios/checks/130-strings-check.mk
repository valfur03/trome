CHECKS += strings-check
CHECK_STEP_strings-check := strings check
.PHONY: strings-check

help::
	@echo "make strings-check       Fail when a build in Xcode would change a String Catalog, when a text of the app or the Live Activity has no French text, or when a French permission text does not say APP_NAME"

strings-check: project
	@$(BUILD_GATE) ./scripts/strings-sync.sh check $(EXPORT_STRINGS)
	@./scripts/strings-check.py $(STRING_CATALOGS)
	@./scripts/app-name-sync.py --check Config/Base.xcconfig App/InfoPlist.xcstrings
