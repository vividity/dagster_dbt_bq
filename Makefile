.PHONY: help build up down restart logs shell dbt-deps seed dbt-build dbt-test dbt-parse defs test lint clean

# The Docker Desktop context is often selected but not running; the system
# daemon at /var/run/docker.sock is the one that works here.
export DOCKER_CONTEXT ?= default

# Compose cannot expand ~ in a volume path, so resolve it here. Every target
# goes through Docker, so the host's Python is never used.
#
# The service-account key lives outside the repo and is mounted read-only. Keep
# it that way — never move it into the working tree.
export SA_KEY_DIR ?= $(HOME)/.config/dagster-dbt-bq
export APP_UID ?= $(shell id -u)
export APP_GID ?= $(shell id -g)

DC := docker compose
# dbt takes its path flags after the subcommand, not before it.
DBT_FLAGS := --project-dir dbt --profiles-dir dbt
# dbt and the linters need no Dagster instance, so they skip the postgres dep.
RUN := $(DC) run --rm --no-deps dagster-webserver
# Anything that loads Definitions builds a DagsterInstance, which needs postgres.
RUN_DB := $(DC) run --rm dagster-webserver

help:
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build: ## Build the image (validates that the dbt project parses)
	$(DC) build

up: ## Start postgres, the webserver (localhost:3000) and the daemon
	$(DC) up -d

down: ## Stop everything (keeps the postgres volume)
	$(DC) down

restart: ## Recreate the Dagster services
	$(DC) up -d --force-recreate dagster-webserver dagster-daemon

logs: ## Follow the Dagster logs
	$(DC) logs -f dagster-webserver dagster-daemon

shell: ## Open a shell in the app image
	$(RUN) bash

dbt-deps: ## Install dbt packages into dbt/dbt_packages (do this first)
	$(RUN) dbt deps $(DBT_FLAGS)

dbt-parse: ## Parse the dbt project — no warehouse connection needed
	$(RUN) dbt parse $(DBT_FLAGS)

seed: ## Load the seed CSVs into BigQuery
	$(RUN) dbt seed $(DBT_FLAGS)

dbt-build: ## Run all dbt models and tests against BigQuery
	$(RUN) dbt build $(DBT_FLAGS)

dbt-test: ## Run the dbt tests only
	$(RUN) dbt test $(DBT_FLAGS)

defs: ## List the Dagster definitions loaded from src/dagster_dbt_bq/defs
	$(RUN_DB) dg list defs

test: ## Python lint, types and unit tests
	$(RUN) sh -c "ruff check src tests && ruff format --check src tests && mypy"
	$(RUN_DB) pytest -q

lint: ## Autofix Python formatting
	$(RUN) sh -c "ruff check --fix src tests && ruff format src tests"

clean: ## Remove containers, volumes and dbt artefacts
	$(DC) down -v
	rm -rf dbt/target dbt/dbt_packages dbt/logs
