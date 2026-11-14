import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from verify_warehouse import findings

GOOD_ACCESS = {
    "DEV_RAW_RW": [("CREATE TABLE", "SCHEMA", "DEV_RAW.LANDING"), ("INSERT", "TABLE", "DEV_RAW.LANDING.T")],
    "DEV_RAW_RO": [("USAGE", "DATABASE", "DEV_RAW"), ("SELECT", "TABLE", "DEV_RAW.LANDING.T")],
    "DEV_ANALYTICS_RW": [("CREATE TABLE", "SCHEMA", "DEV_ANALYTICS.STAGING")],
    "DEV_MARTS_RO": [("USAGE", "DATABASE", "DEV_ANALYTICS"), ("SELECT", "TABLE", "DEV_ANALYTICS.MARTS.F")],
}
BUNDLES = {
    "DEV_LOADER": {"DEV_RAW_RW"},
    "DEV_TRANSFORMER": {"DEV_RAW_RO", "DEV_ANALYTICS_RW"},
    "DEV_ANALYST": {"DEV_MARTS_RO"},
}
USERS = {"DEV_AIRFLOW_SVC": {"DEV_LOADER"}, "DEV_DBT_SVC": {"DEV_TRANSFORMER"}}


def run(access=None, bundles=None, users=None):
    return findings("dev", access or GOOD_ACCESS, bundles or BUNDLES, users or USERS)


def test_design_passes():
    assert run() == []


def test_transformer_writing_raw_is_caught():
    access = {**GOOD_ACCESS, "DEV_RAW_RO": [("INSERT", "TABLE", "DEV_RAW.LANDING.T")]}
    assert any("can write RAW" in f for f in run(access=access))


def test_analyst_reaching_raw_is_caught():
    access = {**GOOD_ACCESS, "DEV_MARTS_RO": [("SELECT", "TABLE", "DEV_RAW.LANDING.T")]}
    assert any("can reach RAW" in f for f in run(access=access))


def test_analyst_reaching_staging_is_caught():
    access = {**GOOD_ACCESS, "DEV_MARTS_RO": [("SELECT", "TABLE", "DEV_ANALYTICS.STAGING.S")]}
    assert any("STAGING" in f for f in run(access=access))


def test_grant_into_another_environment_is_caught():
    access = {**GOOD_ACCESS, "DEV_RAW_RW": [("USAGE", "DATABASE", "PRD_RAW")]}
    assert any("outside its environment" in f for f in run(access=access))


def test_service_user_with_extra_role_is_caught():
    users = {**USERS, "DEV_DBT_SVC": {"DEV_TRANSFORMER", "DEV_LOADER"}}
    assert any("DEV_DBT_SVC" in f for f in run(users=users))


def test_changed_bundle_is_caught():
    bundles = {**BUNDLES, "DEV_ANALYST": {"DEV_MARTS_RO", "DEV_RAW_RO"}}
    assert any("DEV_ANALYST bundles" in f for f in run(bundles=bundles))
