# dagster_dbt_bq

Dagster-orchestrated dbt transformations on Google BigQuery. Everything runs in
Docker — the Dagster webserver, the daemon, and every dbt invocation.

## Quick start

```bash
cp .env.example .env          # GCP_PROJECT=dbtbq-500412

make build                    # build the image
make dbt-deps                 # install dbt packages into dbt/dbt_packages
make up                       # webserver on http://localhost:3000, plus the daemon
make seed && make dbt-build   # load seeds and build the models in BigQuery
```

Auth is a service account whose key lives outside the repo at
`~/.config/dagster-dbt-bq/sa-key.json` and is mounted read-only. No credential
is ever present in the working tree.

`make help` lists every target.

## Layout

| Path | What it is |
| --- | --- |
| `src/dagster_dbt_bq/defs/` | Dagster definitions, loaded by `load_from_defs_folder` |
| `dbt/` | dbt project `bq_analytics` — models, seeds, profile |
| `docker-compose.yml` | postgres + `dagster-webserver` + `dagster-daemon` |
| `dagster.yaml` | Dagster instance config, mounted at `$DAGSTER_HOME` |

The dbt models become Dagster assets automatically via `DbtProjectComponent`;
there is no per-model Python to maintain.

See `CLAUDE.md` for conventions and the version constraints that matter.
