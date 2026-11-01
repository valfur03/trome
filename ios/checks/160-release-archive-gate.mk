CHECKS += release-archive-gate
CHECK_STEP_release-archive-gate := release archive check when the change can alter it
.PHONY: release-archive-gate

help::
	@echo "make release-archive-gate  Run make release-archive-check when the change since main touches what it reads (ios/project.yml, ios/Config/, the Swift files of the types that it looks for, the check itself), else nothing (part of make check)"

# Last: the archive is the longest step, and the cheaper checks fail first. The archive check itself goes through the
# build gate. RELEASE_ARCHIVE_GATE_RUN lets the script test put a stand-in for the archive.
RELEASE_ARCHIVE_GATE_RUN ?= $(MAKE) --no-print-directory release-archive-check
release-archive-gate:
	@status=0; ./scripts/release-archive-gate.py || status=$$?; \
	if [ $$status -eq 0 ]; then $(RELEASE_ARCHIVE_GATE_RUN); elif [ $$status -ne 10 ]; then exit $$status; fi
