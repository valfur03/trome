VIDEO_BASE ?= main
FRAME ?= 60
OPEN ?= 1
QUIET := ../ios/scripts/quiet.sh
LOGS := .build/logs
RENDER := ./scripts/render.sh
MUSIC := public/music.wav
STUDIO_FLAGS := $(if $(PORT),--port $(PORT)) $(if $(filter 0,$(OPEN)),--no-open)

.PHONY: help node-check video-setup video-studio video-still video-clip video-check video-check-if-changed

help:
	@echo "make video-studio        Open the preview studio of the film in the browser (PORT=<n> for a port of your own, OPEN=0 to open no browser); Ctrl-C stops it"
	@echo "make video-still         Render one frame of the film to video/out/still.png (FRAME=<n> for another frame), through the Simulator lock"
	@echo "make video-clip          Render the film with its music to video/out/clip.mp4, through the Simulator lock"
	@echo "make video-check         Film quality gate: type check + unit tests + render one frame and check its size"

node-check:
	@./scripts/node-check.sh

# The packages, then the headless browser that renders the frames (downloaded once, into node_modules).
video-setup: node-check
	@if [ ! -f node_modules/.package-lock.json ] || [ package-lock.json -nt node_modules/.package-lock.json ]; then \
		$(QUIET) $(LOGS)/video-install.log 'added [0-9]+ packages' npm ci; \
	fi
	@$(QUIET) $(LOGS)/video-browser.log '' npx --no-install remotion browser ensure

$(MUSIC): music/synth.ts scripts/make-music.ts src/timing.ts
	@node scripts/make-music.ts $@

video-studio: video-setup $(MUSIC)
	npx --no-install remotion studio $(STUDIO_FLAGS)

video-still: video-setup $(MUSIC)
	@$(RENDER) still Film out/still.png --frame=$(FRAME)

video-clip: video-setup $(MUSIC)
	@$(RENDER) render Film out/clip.mp4

# The render runs outside $(QUIET), so a wait for the Simulator lock shows as it happens.
video-check: video-setup $(MUSIC)
	@$(QUIET) $(LOGS)/video-type-check.log '' npx --no-install tsc
	@$(QUIET) $(LOGS)/video-unit-tests.log '^ℹ (tests|fail) ' node --test "music/**/*.test.ts"
	@$(RENDER) still Film .build/check/still.png --frame=$(FRAME) --log=error
	@node scripts/still-check.ts .build/check/still.png

video-check-if-changed:
	@if ./scripts/video-changed.sh $(VIDEO_BASE); then \
		$(MAKE) --no-print-directory video-check; \
	else \
		echo "video/ has no change since $(VIDEO_BASE): skipping make video-check"; \
	fi
