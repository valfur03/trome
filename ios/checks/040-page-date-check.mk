CHECKS += page-date-check
CHECK_STEP_page-date-check := page date check
.PHONY: page-date-check

help::
	@echo "make page-date-check     Fail when a docs page with a date line says a day older than the last change of its text, or not the same day as the page in the other language"

page-date-check:
	@./scripts/page-date-check.py
