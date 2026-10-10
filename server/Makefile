SERVER_BASE ?= main
PORT ?= $(shell ./scripts/dev-port.sh)
QUIET := ../ios/scripts/quiet.sh
LOGS := .build/logs

export WRANGLER_SEND_METRICS := false

.PHONY: help node-check server-setup server-check server-check-if-changed server-dev server-stop server-login server-secrets server-secret server-counts server-deploy-staging server-deploy

help:
	@echo "make server-setup        Install the packages of the server (server/node_modules), when they are missing or old"
	@echo "make server-check        Server quality gate: no local secrets file that git tracks or does not ignore + no request log at Cloudflare in wrangler.jsonc + generated types up to date + type check + lint + unit tests + script tests"
	@echo "make server-dev          Run the server on this folder's own port ($(PORT); PORT=<n> for another one), with the fake secrets of server/.dev.vars"
	@echo "make server-stop         Stop the server of this folder (make server-dev)"
	@echo "make server-login        Log in to your Cloudflare account (once, before a deploy or a secret); it opens the default browser (LINK=1: it shows a link to open in another browser; CODE=1: a code to type on a Cloudflare page)"
	@echo "make server-secrets      Set each secret of the production Worker in turn (STAGING=1: of the staging Worker), before its first deploy; it asks for each value"
	@echo "make server-secret NAME=<name>  Change one secret of the production Worker (STAGING=1: of the staging Worker); it asks for the value"
	@echo "make server-counts URL=<address>  Show the totals of the server at this address, a line per Paris day of the last 14 days (FULL=1: the whole report as JSON, hour by hour for 30 days, with the errors of 7 days); it asks for the owner token"
	@echo "make server-deploy-staging  Deploy this folder to the staging Worker (needs the Cloudflare account, and make server-secrets STAGING=1 first)"
	@echo "make server-deploy       Deploy main to the production Worker (needs the Cloudflare account and make server-secrets first; main folder, on main, committed)"

node-check:
	@./scripts/node-check.sh

server-setup: node-check
	@if [ ! -f node_modules/.package-lock.json ] || [ package-lock.json -nt node_modules/.package-lock.json ]; then \
		$(QUIET) $(LOGS)/server-install.log 'added [0-9]+ packages' npm ci; \
	fi

server-check: server-setup
	@./scripts/dev-vars-check.sh
	@node scripts/request-log-check.ts
	@$(QUIET) $(LOGS)/server-types-check.log '' npm run --silent types:check
	@$(QUIET) $(LOGS)/server-typecheck.log '' npm run --silent typecheck
	@$(QUIET) $(LOGS)/server-lint.log '' npm run --silent lint
	@$(QUIET) $(LOGS)/server-unit-tests.log '^ +(Test Files|Tests) ' npm test
	@mkdir -p $(LOGS)
	@count=0; for test in ./scripts/tests/*-test.sh; do \
		$$test > $(LOGS)/server-test-scripts.log 2>&1 \
			|| { cat $(LOGS)/server-test-scripts.log; echo "server-test-scripts: FAILED: $$test (its whole output is above, and in server/$(LOGS)/server-test-scripts.log)"; exit 1; }; \
		count=$$((count + 1)); \
	done; \
	echo "server-test-scripts: OK ($$count script tests)"

server-check-if-changed:
	@if ./scripts/server-changed.sh $(SERVER_BASE); then \
		$(MAKE) --no-print-directory server-check; \
	else \
		echo "server/ and contracts/ have no change since $(SERVER_BASE): skipping make server-check"; \
	fi

server-dev: server-setup
	@./scripts/dev.sh $(PORT)

server-stop:
	@./scripts/stop.sh

server-login: server-setup
	@./scripts/login.sh "$(LINK)" "$(CODE)"

server-secrets: server-setup
	@./scripts/put-secrets.sh $(if $(STAGING),staging,production)

server-secret: server-setup
	@if [ -z "$(NAME)" ]; then echo "Give the name of the secret: make server-secret NAME=PRIM_API_KEY (or NAME=APP_TOKEN, or NAME=OWNER_TOKEN)." >&2; exit 1; fi
	./node_modules/.bin/wrangler secret put $(NAME) $(if $(STAGING),--env staging,--env="")

server-counts: node-check
	@./scripts/counts.sh "$(URL)" $(if $(FULL),full,table)

server-deploy-staging: server-check
	@./scripts/deploy.sh staging

server-deploy: server-check
	@./scripts/deploy.sh production
