import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from verify_access import PROBES, Probe, run_probe, run_role


class SnowflakeError(Exception):
    def __init__(self, errno, msg="boom"):
        super().__init__(msg)
        self.errno = errno


def failing(errno):
    def execute(sql):
        raise SnowflakeError(errno)

    return execute


def succeeding(sql):
    return None


ALLOW = Probe("LOADER", "LIST @{env}_RAW.LANDING.S3_LANDING", True, "why")
DENY = Probe("LOADER", "CREATE ROLE {env}_X", False, "why")


def test_allowed_probe_that_works_is_clean():
    assert run_probe(succeeding, ALLOW, "DEV") is None


def test_allowed_probe_that_fails_is_a_finding():
    assert "expected to work" in run_probe(failing(3001), ALLOW, "DEV")


def test_denied_probe_refused_is_clean():
    for number in (3001, 2003, 2043):
        assert run_probe(failing(number), DENY, "DEV") is None


def test_denied_probe_that_succeeds_is_a_finding():
    assert "but it succeeded" in run_probe(succeeding, DENY, "DEV")


def test_denied_probe_failing_for_another_reason_is_a_finding():
    # e.g. a syntax error must not count as a refusal
    assert "expected a refusal, got 1003" in run_probe(failing(1003), DENY, "DEV")


def test_environment_is_substituted():
    seen = []
    run_probe(seen.append, ALLOW, "PRD")
    assert seen == ["LIST @PRD_RAW.LANDING.S3_LANDING"]


def test_every_role_has_allowed_and_denied_probes():
    for role in ("LOADER", "TRANSFORMER", "ANALYST"):
        mine = [p for p in PROBES if p.role == role]
        assert any(p.allowed for p in mine) and any(not p.allowed for p in mine)


def test_run_role_collects_only_misbehaving_probes():
    assert run_role(succeeding, "ANALYST", "DEV")  # the denials "succeeded"
