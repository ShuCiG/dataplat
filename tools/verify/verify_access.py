"""Prove the access model by using it: sign in as each functional role and try things.

`verify_warehouse.py` reads the grants. This script does what a person would do to be sure:
it becomes the loader, the transformer and the analyst in turn, runs statements that must work and
statements that must be refused, and fails when any result differs.

The functional roles have no user the Terraform login can borrow, so for the duration of the run
`PLATFORM_ADMIN` creates one throw-away key-pair user per role, grants it that role and nothing
else, and drops it at the end (also when a probe fails). Nothing is left behind and no key is
stored: the private key lives in memory.

    SNOWFLAKE_ORGANIZATION_NAME=... SNOWFLAKE_ACCOUNT_NAME=... SNOWFLAKE_USER=... \\
    SNOWFLAKE_TOKEN=... python verify_access.py dev

Every refusal must be a real one. A statement that fails because an object is missing would look
like a pass, so refusals are matched on Snowflake's error numbers and the probes use objects that
Terraform guarantees exist (databases, schemas, the stage).
"""

from __future__ import annotations

import os
import sys
from collections.abc import Callable
from dataclasses import dataclass

# Snowflake error numbers that mean "you may not".
INSUFFICIENT = 3001  # Insufficient privileges to operate on ...
NOT_AUTHORIZED = {2003, 2043}  # ... does not exist or not authorized
REFUSED = {INSUFFICIENT} | NOT_AUTHORIZED


@dataclass(frozen=True)
class Probe:
    role: str  # functional role without the environment prefix
    sql: str  # {env} is replaced by the upper-case environment name
    allowed: bool
    why: str


PROBES = [
    # LOADER: writes RAW, sees nothing else.
    Probe("LOADER", "LIST @{env}_RAW.LANDING.S3_LANDING", True, "loader reads the landing stage"),
    Probe(
        "LOADER",
        "CREATE TEMPORARY TABLE {env}_RAW.LANDING.ACCESS_PROBE (i INT)",
        True,
        "loader creates tables in RAW.LANDING",
    ),
    Probe("LOADER", "USE SCHEMA {env}_ANALYTICS.MARTS", False, "loader cannot reach the marts"),
    Probe("LOADER", "USE SCHEMA {env}_ANALYTICS.STAGING", False, "loader cannot reach staging"),
    Probe(
        "LOADER",
        "CREATE SCHEMA {env}_ANALYTICS.ACCESS_PROBE",
        False,
        "loader cannot create schemas in ANALYTICS",
    ),
    Probe("LOADER", "CREATE ROLE {env}_ACCESS_PROBE", False, "loader cannot create roles"),
    # TRANSFORMER: reads RAW, builds ANALYTICS, writes nothing in RAW.
    Probe("TRANSFORMER", "USE SCHEMA {env}_RAW.LANDING", True, "transformer reads RAW"),
    Probe(
        "TRANSFORMER",
        "CREATE TEMPORARY TABLE {env}_ANALYTICS.STAGING.ACCESS_PROBE (i INT)",
        True,
        "transformer builds in STAGING",
    ),
    Probe(
        "TRANSFORMER",
        "CREATE TEMPORARY TABLE {env}_ANALYTICS.MARTS.ACCESS_PROBE (i INT)",
        True,
        "transformer builds in MARTS",
    ),
    Probe(
        "TRANSFORMER",
        "CREATE TABLE {env}_RAW.LANDING.ACCESS_PROBE (i INT)",
        False,
        "transformer cannot create tables in RAW",
    ),
    Probe(
        "TRANSFORMER",
        "CREATE SCHEMA {env}_RAW.ACCESS_PROBE",
        False,
        "transformer cannot create schemas in RAW",
    ),
    Probe("TRANSFORMER", "CREATE ROLE {env}_ACCESS_PROBE", False, "transformer cannot create roles"),
    Probe(
        "TRANSFORMER",
        "CREATE STORAGE INTEGRATION {env}_ACCESS_PROBE TYPE = EXTERNAL_STAGE "
        "STORAGE_PROVIDER = 'S3' ENABLED = FALSE "
        "STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::000000000000:role/x' "
        "STORAGE_ALLOWED_LOCATIONS = ('s3://x/')",
        False,
        "transformer cannot create integrations",
    ),
    # ANALYST: the marts and nothing else.
    Probe("ANALYST", "USE SCHEMA {env}_ANALYTICS.MARTS", True, "analyst reads the marts"),
    Probe("ANALYST", "USE SCHEMA {env}_RAW.LANDING", False, "analyst cannot see RAW"),
    Probe("ANALYST", "USE SCHEMA {env}_ANALYTICS.STAGING", False, "analyst cannot see staging"),
    Probe("ANALYST", "USE SCHEMA {env}_ANALYTICS.INTERMEDIATE", False, "analyst cannot see intermediate"),
    Probe(
        "ANALYST",
        "CREATE TABLE {env}_ANALYTICS.MARTS.ACCESS_PROBE (i INT)",
        False,
        "analyst cannot write the marts",
    ),
    Probe("ANALYST", "LIST @{env}_RAW.LANDING.S3_LANDING", False, "analyst cannot list the landing stage"),
]


def errno_of(exc: Exception) -> int | None:
    return getattr(exc, "errno", None)


def run_probe(execute: Callable[[str], object], probe: Probe, env: str) -> str | None:
    """Run one probe as the session behind `execute`. Return a finding, or None when it behaved."""
    sql = probe.sql.format(env=env)
    try:
        execute(sql)
    except Exception as exc:
        number = errno_of(exc)
        if probe.allowed:
            return f"{env}_{probe.role}: {probe.why}: expected to work, got {number}: {_first_line(exc)}"
        if number in REFUSED:
            return None
        return f"{env}_{probe.role}: {probe.why}: expected a refusal, got {number}: {_first_line(exc)}"
    if probe.allowed:
        return None
    return f"{env}_{probe.role}: {probe.why}: expected a refusal, but it succeeded: {sql}"


def _first_line(exc: Exception) -> str:
    return (str(exc).splitlines() or [""])[0]


def run_role(execute: Callable[[str], object], role: str, env: str) -> list[str]:
    return [f for p in PROBES if p.role == role if (f := run_probe(execute, p, env))]


def user_name(env: str, role: str) -> str:
    return f"{env}_ACCESS_PROBE_{role}"


def new_key_pair() -> tuple[bytes, str]:
    """Return (private key as DER for the connector, public key as base64 for Snowflake)."""
    import base64

    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import rsa

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    der = key.private_bytes(
        serialization.Encoding.DER,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )
    pub = key.public_key().public_bytes(
        serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo
    )
    return der, base64.b64encode(pub).decode()


def account() -> str:
    return f"{os.environ['SNOWFLAKE_ORGANIZATION_NAME']}-{os.environ['SNOWFLAKE_ACCOUNT_NAME']}"


def admin_connection():
    import snowflake.connector

    return snowflake.connector.connect(
        account=account(),
        user=os.environ["SNOWFLAKE_USER"],
        authenticator="WORKLOAD_IDENTITY",
        workload_identity_provider=os.environ.get("SNOWFLAKE_WORKLOAD_IDENTITY_PROVIDER", "OIDC"),
        token=os.environ.get("SNOWFLAKE_TOKEN"),
        role="PLATFORM_ADMIN",
    )


def probe_connection(user: str, role: str, private_key: bytes):
    import snowflake.connector

    return snowflake.connector.connect(account=account(), user=user, private_key=private_key, role=role)


def main(
    argv: list[str], admin_fn: Callable = admin_connection, probe_fn: Callable = probe_connection
) -> int:
    if len(argv) != 2:
        print("usage: verify_access.py <env>", file=sys.stderr)
        return 2
    env = argv[1].upper()
    roles = sorted({p.role for p in PROBES})
    admin = admin_fn()
    problems: list[str] = []
    created: list[str] = []
    try:
        cur = admin.cursor()
        for role in roles:
            user = user_name(env, role)
            cur.execute(f"DROP USER IF EXISTS {user}")
            private_key, public_key = new_key_pair()
            cur.execute(
                f"CREATE USER {user} TYPE = SERVICE RSA_PUBLIC_KEY = '{public_key}' "
                f"DEFAULT_ROLE = {env}_{role} COMMENT = 'throw-away user of verify_access.py'"
            )
            created.append(user)
            cur.execute(f"GRANT ROLE {env}_{role} TO USER {user}")
            session = probe_fn(user, f"{env}_{role}", private_key)
            try:
                scur = session.cursor()
                problems += run_role(scur.execute, role, env)
            finally:
                session.close()
    finally:
        cleanup = admin.cursor()
        for user in created:
            try:
                cleanup.execute(f"DROP USER IF EXISTS {user}")
            except Exception as exc:
                problems.append(f"could not drop {user}: {_first_line(exc)}")
        admin.close()

    for p in problems:
        print(f"FAIL {p}")
    checked = len(PROBES)
    print(f"{env}: {f'FAILED, {len(problems)} of {checked} probes' if problems else f'ok, {checked} probes'}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
