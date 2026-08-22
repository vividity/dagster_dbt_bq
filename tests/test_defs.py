"""Smoke tests for the Dagster definitions.

These load the real definitions, which compiles the dbt manifest, so they catch
a broken dbt project or a mis-wired component without touching BigQuery.
Requires dbt/dbt_packages and dbt/target/manifest.json; `make test`
depends on dbt-parse for the latter, and `make dbt-deps` provides the former.
"""

from dagster import AssetKey

from dagster_dbt_bq.definitions import defs

# DbtProjectComponent prefixes each asset key with the model's folder under
# models/, so these mirror the dbt layer layout rather than the bare model name.
EXPECTED_ASSETS = {
    AssetKey(["staging", "stg_customers"]),
    AssetKey(["staging", "stg_orders"]),
    AssetKey(["staging", "stg_payments"]),
    AssetKey(["marts", "fct_orders"]),
    AssetKey(["marts", "dim_customers"]),
}


def test_every_dbt_model_is_an_asset() -> None:
    keys = {spec.key for spec in defs().resolve_all_asset_specs()}
    assert keys >= EXPECTED_ASSETS


def test_dbt_tests_become_asset_checks() -> None:
    check_keys = defs().resolve_asset_graph().asset_check_keys
    assert check_keys, "expected the dbt generic tests to load as asset checks"
    assert {key.asset_key for key in check_keys} <= EXPECTED_ASSETS
