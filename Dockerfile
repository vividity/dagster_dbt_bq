# dagster-dbt does not support Python 3.14, so the interpreter is pinned here
# rather than inherited from whatever the host happens to have.
FROM python:3.12-slim-trixie

COPY --from=ghcr.io/astral-sh/uv:0.12.3 /uv /usr/local/bin/uv

# git is required by `dbt deps` for git-sourced packages, and `dbt debug`
# reports a failed check without it.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

# The venv lives outside the workdir so bind-mounting source over the workdir at
# runtime cannot shadow it.
ENV UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    DAGSTER_HOME=/opt/dagster/home

# uid 1000 matches the host user, so the read-only ADC mount (mode 0600) is
# readable inside the container.
ARG APP_UID=1000
ARG APP_GID=1000
RUN groupadd -g "${APP_GID}" app \
    && useradd -m -u "${APP_UID}" -g "${APP_GID}" -s /bin/bash app \
    && mkdir -p /opt/dagster/home /opt/dagster/app /opt/venv \
    && chown -R app:app /opt/dagster /opt/venv

WORKDIR /opt/dagster/app

# Dependency layer first: it only rebuilds when the lockfile changes.
COPY --chown=app:app pyproject.toml uv.lock ./
COPY --chown=app:app src/ ./src/
RUN uv sync --frozen --group dev

COPY --chown=app:app dbt/ ./dbt/
COPY --chown=app:app tests/ ./tests/

USER app

# Validate at build time that the dbt project resolves and parses. `dbt parse`
# needs no warehouse connection, so the build stays offline and deterministic.
# The runtime bind mount replaces ./dbt, so this is a check, not a cache — use
# `make dbt-deps` to populate dbt_packages/ in the working tree.
RUN dbt deps --project-dir dbt --profiles-dir dbt \
    && dbt parse --project-dir dbt --profiles-dir dbt \
    && rm -rf dbt/logs

EXPOSE 3000
CMD ["dagster-webserver", "-h", "0.0.0.0", "-p", "3000"]
