CHECKS += prose-check
CHECK_STEP_prose-check := Markdown line check
.PHONY: prose-check

help::
	@echo "make prose-check         Fail when a line of prose of a Markdown or MDX file of the repo is longer than 400 characters (write one sentence per line)"

prose-check:
	@./scripts/prose-check.py
