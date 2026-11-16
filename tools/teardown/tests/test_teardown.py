import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import teardown


def test_stack_order_puts_dependants_first():
    assert teardown.STACKS == ["30-dbt-runtime", "20-warehouse", "10-platform"]


@pytest.mark.parametrize(
    "environment, expected", [("dev", True), ("tst", True), ("stg", False), ("prd", False)]
)
def test_data_loss_flag_is_read_from_env_files(environment, expected):
    text = teardown.tfvars_path(environment).read_text(encoding="utf-8")
    assert teardown.allows_data_loss(text) is expected


def test_missing_flag_counts_as_protected():
    assert teardown.allows_data_loss('environment = "x"\n') is False


def test_missing_settings_lists_everything_absent():
    assert set(teardown.missing_settings({})) == {
        "AWS_PROFILE",
        "SNOWFLAKE_USER",
        "SNOWFLAKE_AUTHENTICATOR",
        "SNOWFLAKE_WORKLOAD_IDENTITY_PROVIDER",
        "SNOWFLAKE_ORGANIZATION_NAME",
        "SNOWFLAKE_ACCOUNT_NAME",
    }


def test_nothing_missing_when_all_set():
    names = ["AWS_PROFILE", *teardown.SNOWFLAKE_VARS, *teardown.SNOWFLAKE_ACCOUNT_VARS]
    environ = dict.fromkeys(names, "x")
    assert teardown.missing_settings(environ) == []


def test_backend_key_is_per_environment_and_stack():
    args = teardown.backend_args("dev", "20-warehouse")
    assert "-backend-config=key=dev/20-warehouse/terraform.tfstate" in args


def test_execute_on_protected_environment_needs_flag(monkeypatch, capsys):
    for name in ["AWS_PROFILE", *teardown.SNOWFLAKE_VARS, *teardown.SNOWFLAKE_ACCOUNT_VARS]:
        monkeypatch.setenv(name, "x")
    monkeypatch.setattr(teardown, "run_stack", lambda *a, **k: pytest.fail("must not run"))
    assert teardown.main(["prd", "--execute"]) == 2
    assert "allow_data_loss" in capsys.readouterr().err


def test_unknown_environment_is_refused(capsys):
    assert teardown.main(["nope"]) == 2
    assert "Unknown environment" in capsys.readouterr().err
