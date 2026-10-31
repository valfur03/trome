VIDEO_BASE ?= main
FRAME ?= 60
OPEN ?= 1
QUIET := ../ios/scripts/quiet.sh
LOGS := .build/logs
RENDER := ./scripts/render.sh
MUSIC := public/music.wav
# The pictures of the app that the film shows: copies of the docs captures and of the app icon, made by make, never kept in git.
SCREENSHOTS := ../docs/src/assets/screenshots
APP_PICTURES := $(foreach lang,fr en,$(foreach case,metro rer fork,public/app/live-activity-$(case)-$(lang).png)) public/app/app-icon.png
# The key frames show the captures of the film (make film-captures) in Apple's iPhone bezel: neither is kept in git.
BEZEL ?= $(HOME)/Library/Application Support/TROME/store-bezel.png
FILM_CAPTURES := ../ios/.build/film-captures/captures
STUDIO_FLAGS := $(if $(PORT),--port $(PORT)) $(if $(filter 0,$(OPEN)),--no-open)

.PHONY: help node-check film-pictures video-setup video-studio video-still video-clip video-stills video-check video-check-if-changed

help:
	@echo "make video-studio        Open the preview studio of the film in the browser (PORT=<n> for a port of your own, OPEN=0 to open no browser); Ctrl-C stops it"
	@echo "make video-still         Render one frame of the film to video/out/still.png (FRAME=<n> for another frame), through the Simulator lock"
	@echo "make video-clip          Render the film with its music to video/out/clip.mp4, through the Simulator lock"
	@echo "make video-stills        Render the key frames of the storyboard (two looks, French and English) and its page in each language to video/out/stills/, through the Simulator lock (needs make film-captures, and BEZEL=<path> when the bezel is not in its place)"
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

public/app/live-activity-%.png: $(SCREENSHOTS)/live-activity-%.png
	@mkdir -p public/app && cp $< $@

public/app/app-icon.png: ../ios/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
	@mkdir -p public/app && cp $< $@

film-pictures:
	@./scripts/film-pictures.sh "$(BEZEL)" $(FILM_CAPTURES) public/app

video-studio: video-setup $(MUSIC) $(APP_PICTURES)
	npx --no-install remotion studio $(STUDIO_FLAGS)

video-still: video-setup $(MUSIC) $(APP_PICTURES)
	@$(RENDER) still Film out/still.png --frame=$(FRAME)

video-clip: video-setup $(MUSIC) $(APP_PICTURES)
	@$(RENDER) render Film out/clip.mp4

# One PNG per key frame (the Stills composition: one frame per key frame, in the order of src/arrival.ts), named by
# scripts/name-stills.ts, and the storyboard on one page in each language.
video-stills: video-setup $(APP_PICTURES) film-pictures
	@rm -rf out/stills
	@$(RENDER) render Stills out/stills --sequence --image-format=png
	@node scripts/name-stills.ts out/stills
	@$(RENDER) still Storyboard out/stills/storyboard-fr.png --props='{"lang":"fr"}'
	@$(RENDER) still Storyboard out/stills/storyboard-en.png --props='{"lang":"en"}'

# The render runs outside $(QUIET), so a wait for the Simulator lock shows as it happens.
video-check: video-setup $(MUSIC) $(APP_PICTURES)
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
