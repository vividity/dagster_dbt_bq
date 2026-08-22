# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Dagster orchestrating a dbt project against Google BigQuery. The dbt models are
exposed as Dagster assets automatically by `DbtProjectComponent` — there is no
per-model Python, and adding a `.sql` file is all it takes to add an asset.

Names to keep straight:

- repo / Python package: **`dagster_dbt_bq`**
- dbt project and profile: **`bq_analytics`** — a dbt project may *not* be named
  `dbt_bigquery`, that name is reserved by the BigQuery adapter.

## Everything runs in Docker

There is no host virtualenv and you should not create one. `make` is the only
entry point; each target shells into the container.

```bash
make help          # list every target
make build         # build the image; also validates that the dbt project parses
make dbt-deps      # populate dbt/dbt_packages — required before anything loads defs
make up            # postgres + webserver (localhost:3000) + daemon
make defs          # list the Dagster assets/checks resolved from the dbt manifest
make test          # ruff + mypy, then pytest
make dbt-build     # dbt run + dbt test against BigQuery
make down          # stop; `make clean` also drops the volume and dbt artefacts
```

Run one dbt selection ad hoc — dbt takes its path flags *after* the subcommand:

```bash
docker compose run --rm --no-deps dagster-webserver \
  dbt build --project-dir dbt --profiles-dir dbt --select stg_orders+
```

Run a single test: `docker compose run --rm dagster-webserver pytest -q tests/test_defs.py::test_every_dbt_model_is_an_asset`

Both of those need `GCLOUD_CONFIG_DIR`/`APP_UID`/`APP_GID` exported, which the
Makefile does for you — prefer `make shell` and run the command inside.

## Version constraints that will bite you

| Constraint | Consequence |
| --- | --- |
| `dagster-dbt==0.29.19` requires `dbt-core<1.12` | dbt is pinned to **1.11.14** / dbt-bigquery **1.11.3**. Bumping dbt to 1.12 breaks the install; bump `dagster-dbt` in the same commit or not at all. |
| `dagster-dbt` requires Python `<3.14` | The image pins **3.12**. The host interpreter here is 3.14 and cannot run this project — that is the main reason for Docker. |
| Dagster libraries are version-locked to each other | `dagster`, `dagster-dbt`, `dagster-postgres`, `dagster-webserver` and `dagster-dg-cli` must move together (`1.13.19` / `0.29.19`). |

After changing `pyproject.toml`: `uv lock --python 3.12 && make build`.

## Auth and configuration — the key never enters the repo

dbt authenticates as the service account
**`dagster-dbt-bq@dbtbq-500412.iam.gserviceaccount.com`** (roles
`bigquery.jobUser` + `bigquery.dataEditor` on project `dbtbq-500412`).

The key lives **outside the working tree** at `~/.config/dagster-dbt-bq/sa-key.json`
(mode 0600) and is bind-mounted read-only to `/var/secrets/google` in the
container. Only the *path* travels through config, via `DBT_BIGQUERY_KEYFILE`.
This is deliberate: no credential is reachable from the repo, so none can be
committed. `.gitignore` also carries `*sa-key*.json`, `*service-account*.json`,
`*-credentials.json` and `secrets/` as a backstop.

**Never copy the key into the repo, echo its contents, or paste it into a file
here.** If a new key is ever needed, write it to `$SA_KEY_DIR` and nowhere else.

The container runs as uid 1000 so it can read that 0600 file — set
`APP_UID`/`APP_GID` in `.env` if your uid differs.

```bash
cp .env.example .env    # GCP_PROJECT=dbtbq-500412
make dbt-parse          # offline check
```

Connection settings reach dbt only through `env_var()` in `dbt/profiles.yml`
(`DBT_BIGQUERY_KEYFILE` / `_PROJECT` / `_DATASET` / `_LOCATION`). Never hardcode
a project, dataset or path in a model or in `dbt_project.yml`.

Note the host `gcloud` CLI has **no active account** (`gcloud auth list` is
empty); only Application Default Credentials exist, and the project no longer
depends on them. Admin calls against GCP can use
`gcloud auth application-default print-access-token` with the REST API.

## Where the data lands

`dataset` is the *base* name; each layer appends its own suffix, so with
`DBT_BIGQUERY_DATASET=dbt_dev` you get:

| Dataset | Contents |
| --- | --- |
| `dbt_dev` | the three seed tables |
| `dbt_dev_staging` | `stg_*` views |
| `dbt_dev_marts` | `fct_orders`, `dim_customers` tables |

## Docker context

The `desktop-linux` context is usually selected on this machine but its daemon is
not running. The Makefile exports `DOCKER_CONTEXT ?= default` to reach the
system daemon instead of mutating global docker config. Any raw `docker` command
you run outside `make` needs the same export.

## dbt layering

```
seeds → staging → marts
```

- **staging** — views, schema `staging`, one `stg_<entity>` per raw input.
  Rename, cast, light derivation. No joins, no aggregation, no business logic.
- **marts** — tables, schema `marts`, `dim_` or `fct_` prefix. The public
  interface.

Conventions:

- Every model opens with CTEs importing its `ref()`s, then does the work; the
  final `select` reads from a named CTE.
- `select *` only inside that initial import CTE.
- Seed column types are pinned in `dbt_project.yml` so BigQuery loads the CSVs
  identically everywhere — extend that block when you add a seed.
- Tests and descriptions live in `_staging.yml` / `_marts.yml` beside the models.
  Generic tests use the dbt 1.10+ `data_tests:` + `arguments:` form.

Asset keys are prefixed with the folder under `models/`, so `stg_orders` is the
Dagster asset `staging/stg_orders`, not `stg_orders`. Tests attached to a model
load as Dagster **asset checks** on it.

## Generated paths, not source

- `src/dagster_dbt_bq/defs/.local_defs_state/` — `DbtProjectComponent` caches a
  compiled copy of the whole dbt project here. Gitignored; never edit it, and
  delete it if the manifest looks stale.
- `dbt/dbt_packages/` — populated by `make dbt-deps`. `dbt/package-lock.yml` *is*
  committed; the `.concurrent-update-lock` beside it is not.

## The seed data is a placeholder

`dbt/seeds/` holds the three jaffle_shop CSVs, and the five models over them
exist so the Docker → ADC → BigQuery chain is verifiable end to end on a fresh
clone. They are scaffolding: delete them when real sources arrive.
