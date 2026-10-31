CHECKS += public-text-check
CHECK_STEP_public-text-check := public text check
.PHONY: public-text-check

help::
	@echo "make public-text-check   Fail when a file of the repo has a backlog id, a word of the team's own process, a personal email address, a local path, the old name of the app, or \"we\" in the prose"

public-text-check:
	@./scripts/public-text-check.py
