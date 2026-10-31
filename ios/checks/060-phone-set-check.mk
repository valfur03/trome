CHECKS += phone-set-check
CHECK_STEP_phone-set-check := phone set check
.PHONY: phone-set-check

help::
	@echo "make phone-set-check     Fail when a recorded phone set of contracts/phone/ changed, moved, went or grew while its build is in the field (part of make check)"

phone-set-check:
	@./scripts/phone-set-check.py check
