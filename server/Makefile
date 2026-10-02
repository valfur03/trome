SERVER_BASE ?= main
PORT ?= $(shell ./scripts/dev-port.sh)
BUILD_DIR := .wrangler

export WRANGLER_SEND_METRICS := false

.PHONY: help node-check server-setup server-check server-check-if-changed server-dev server-stop server-login server-secrets server-secret server-deploy-staging server-deploy

help:
	@echo "make server-setup        Install the packages of the server (server/node_modules), when they are missing or old"
	@echo "make server-check        Server quality gate: no local secrets file in git + generated types up to date + type check + lint + unit tests + script tests"
	@echo "make server-dev          Run the server on this folder's own port ($(PORT); PORT=<n> for another one), with the fake secrets of server/.dev.vars"
	@echo "make server-stop         Stop the server of this folder (make server-dev)"
	@echo "make server-login        Log in to your Cloudflare account (once, before a deploy or a secret)"
	@echo "make server-secrets      Set each secret of the production Worker in turn (STAGING=1: of the staging Worker), before its first deploy; it asks for each value"
	@echo "make server-secret NAME=<name>  Change one secret of the production Worker (STAGING=1: of the staging Worker); it asks for the value"
	@echo "make server-deploy-staging  Deploy this folder to the staging Worker (needs the Cloudflare account, and make server-secrets STAGING=1 first)"
	@echo "make server-deploy       Deploy main to the production Worker (needs the Cloudflare account and make server-secrets first; main folder, on main, committed)"

node-check:
	@./scripts/node-check.sh

server-setup: node-check
	@if [ ! -f node_modules/.package-lock.json ] || [ package-lock.json -nt node_modules/.package-lock.json ]; then \
		npm ci; \
	fi

server-check: server-setup
	@./scripts/dev-vars-check.sh
	npm run --silent types:check
	npm run --silent typecheck
	npm run --silent lint
	npm test
	@mkdir -p $(BUILD_DIR)
	@for test in ./scripts/tests/*-test.sh; do \
		$$test > $(BUILD_DIR)/test-scripts.log 2>&1 || { cat $(BUILD_DIR)/test-scripts.log; exit 1; }; \
	done
	@echo "Server scripts: all tests passed"

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
	./node_modules/.bin/wrangler login

server-secrets: server-setup
	@./scripts/put-secrets.sh $(if $(STAGING),staging,production)

server-secret: server-setup
	@if [ -z "$(NAME)" ]; then echo "Give the name of the secret: make server-secret NAME=PRIM_API_KEY (or NAME=APP_TOKEN)." >&2; exit 1; fi
	./node_modules/.bin/wrangler secret put $(NAME) $(if $(STAGING),--env staging,--env="")

server-deploy-staging: server-check
	@./scripts/deploy.sh staging

server-deploy: server-check
	@./scripts/deploy.sh production
