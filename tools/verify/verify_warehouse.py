"""Check that an environment's Snowflake access model is what the warehouse stack promises.

Runs after every apply, before the change is promoted to the next environment. It only reads
(SHOW GRANTS, LIST), so it is safe to run anywhere the Terraform login works:

    SNOWFLAKE_ORGANIZATION_NAME=... SNOWFLAKE_ACCOUNT_NAME=... SNOWFLAKE_USER=... \\
    SNOWFLAKE_TOKEN=... python verify_warehouse.py dev

The Terraform user cannot assume the functional roles, so the checks are on the grants: what
each functional role can reach through the access roles it bundles. A live login as the service
users is exercised later, by dbt and the orchestrator.
"""

from __future__ import annotations

import os
import sys
from collections.abc import Callable

# Privileges that only read. Anything else on RAW for the transformer is a finding.
READ_ONLY = {"USAGE", "SELECT", "REFERENCES", "MONITOR"}

# functional role -> (access roles it must bundle exactly, service user bound to it or None)
FUNCTIONAL = {
    "LOADER": ({"RAW_RW"}, "AIRFLOW_SVC"),
    "TRANSFORMER": ({"RAW_RO", "ANALYTICS_RW"}, "DBT_SVC"),
    "ANALYST": ({"MARTS_RO"}, None),
}

Grant = tuple[str, str, str]  # (privilege, object type, object name)


def schema_of(name: str) -> tuple[str, str]:
    """Split 'DB.SCHEMA.OBJECT' into (database, schema); missing parts are ''."""
    parts = name.replace('"', "").split(".")
    return parts[0], parts[1] if len(parts) > 1 else ""


def findings(
    env: str,
    access: dict[str, list[Grant]],
    bundles: dict[str, set[str]],
    users: dict[str, set[str]],
) -> list[str]:
    """Return every way the grants deviate from the design. Empty means the environment is fine."""
    env = env.upper()
    raw, analytics = f"{env}_RAW", f"{env}_ANALYTICS"
    out: list[str] = []

    for role, (expected, svc_user) in FUNCTIONAL.items():
        name = f"{env}_{role}"
        got = bundles.get(name, set())
        want = {f"{env}_{a}" for a in expected}
        if got != want:
            out.append(f"{name} bundles {sorted(got)}, expected {sorted(want)}")
        if svc_user:
            held = users.get(f"{env}_{svc_user}", set())
            if held != {name}:
                out.append(f"{env}_{svc_user} holds {sorted(held)}, expected only {name}")

        for access_role in got:
            for privilege, kind, obj in access.get(access_role, []):
                if kind == "ROLE":
                    continue
                db, schema = schema_of(obj)
                if not db.startswith(f"{env}_"):
                    out.append(f"{name} reaches {kind} {obj} outside its environment")
                elif role == "ANALYST" and db == raw:
                    out.append(f"{name} can reach RAW: {privilege} on {kind} {obj}")
                elif role == "ANALYST" and db == analytics and schema not in ("", "MARTS"):
                    out.append(f"{name} can reach {schema}: {privilege} on {kind} {obj}")
                elif role == "TRANSFORMER" and db == raw and privilege not in READ_ONLY:
                    out.append(f"{name} can write RAW: {privilege} on {kind} {obj}")
                elif role == "LOADER" and db == analytics:
                    out.append(f"{name} can reach ANALYTICS: {privilege} on {kind} {obj}")
    return out


def _rows(cur, sql: str) -> list[dict]:
    cur.execute(sql)
    cols = [c[0].lower() for c in cur.description]
    return [dict(zip(cols, r, strict=True)) for r in cur.fetchall()]


def collect(cur, env: str) -> tuple[dict[str, list[Grant]], dict[str, set[str]], dict[str, set[str]]]:
    """Read the grants of this environment's access and functional roles from Snowflake."""
    access: dict[str, list[Grant]] = {}
    bundles: dict[str, set[str]] = {}
    users: dict[str, set[str]] = {}
    for a in ("RAW_RW", "RAW_RO", "ANALYTICS_RW", "MARTS_RO"):
        role = f"{env}_{a}"
        grants = [
            (r["privilege"], r["granted_on"], r["name"]) for r in _rows(cur, f"SHOW GRANTS TO ROLE {role}")
        ]
        grants += [
            (r["privilege"], r["grant_on"], r["name"])
            for r in _rows(cur, f"SHOW FUTURE GRANTS TO ROLE {role}")
        ]
        access[role] = grants
    for f, (_, svc_user) in FUNCTIONAL.items():
        role = f"{env}_{f}"
        bundles[role] = {
            r["name"]
            for r in _rows(cur, f"SHOW GRANTS TO ROLE {role}")
            if r["granted_on"] == "ROLE" and r["name"].startswith(f"{env}_")
        }
        if svc_user:
            users[f"{env}_{svc_user}"] = {
                r["role"]
                for r in _rows(cur, f"SHOW GRANTS TO USER {env}_{svc_user}")
                if r.get("granted_on", "ROLE") == "ROLE"
            }
    return access, bundles, users


def connect():
    import snowflake.connector

    return snowflake.connector.connect(
        account=f"{os.environ['SNOWFLAKE_ORGANIZATION_NAME']}-{os.environ['SNOWFLAKE_ACCOUNT_NAME']}",
        user=os.environ["SNOWFLAKE_USER"],
        authenticator="WORKLOAD_IDENTITY",
        workload_identity_provider=os.environ.get("SNOWFLAKE_WORKLOAD_IDENTITY_PROVIDER", "OIDC"),
        token=os.environ.get("SNOWFLAKE_TOKEN"),
        role="PLATFORM_ADMIN",
    )


def main(argv: list[str], connect_fn: Callable = connect) -> int:
    if len(argv) != 2:
        print("usage: verify_warehouse.py <env>", file=sys.stderr)
        return 2
    env = argv[1].upper()
    con = connect_fn()
    try:
        cur = con.cursor()
        problems = findings(env, *collect(cur, env))
        # The S3 integration works only if Snowflake can really list the bucket.
        try:
            cur.execute(f"LIST @{env}_RAW.LANDING.S3_LANDING")
            cur.fetchall()
        except Exception as exc:
            problems.append(f"cannot list the landing stage: {str(exc).splitlines()[0]}")
    finally:
        con.close()

    for p in problems:
        print(f"FAIL {p}")
    print(f"{env}: {f'FAILED, {len(problems)} finding(s)' if problems else 'ok'}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
