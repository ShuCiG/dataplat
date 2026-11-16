"""Tear down one environment: the dbt task definition, the Snowflake objects, then the AWS platform.

    python tools/teardown/teardown.py dev                  # dry run: shows what would be destroyed
    python tools/teardown/teardown.py dev --execute        # destroys it, after you type the environment name
    python tools/teardown/teardown.py prd --execute --allow-data-loss

Only what the three Terraform stacks created is touched. Snowflake objects of other projects in the
same account, the bootstrap objects (PLATFORM_ADMIN, TERRAFORM_* users) and `infra/bootstrap/aws`
are not part of any environment and stay: see "Tear everything down" in docs/runbook.md.

Credentials come from the shell, exactly as for a manual `terraform` run: an AWS profile for the
environment, and for the warehouse stack the SNOWFLAKE_* variables. The script checks they are there
before it starts, so it does not stop halfway.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INFRA = ROOT / "infra"

# Later stacks read from earlier ones, so they go first.
STACKS = ["30-dbt-runtime", "20-warehouse", "10-platform"]

SNOWFLAKE_VARS = ["SNOWFLAKE_USER", "SNOWFLAKE_AUTHENTICATOR", "SNOWFLAKE_WORKLOAD_IDENTITY_PROVIDER"]
SNOWFLAKE_ACCOUNT_VARS = ["SNOWFLAKE_ORGANIZATION_NAME", "SNOWFLAKE_ACCOUNT_NAME"]


def tfvars_path(environment: str) -> Path:
    return INFRA / "envs" / f"{environment}.tfvars"


def allows_data_loss(tfvars_text: str) -> bool:
    """Whether the environment file lets terraform delete buckets and repositories that hold data."""
    match = re.search(r"^\s*allow_data_loss\s*=\s*(true|false)\s*$", tfvars_text, re.MULTILINE)
    return bool(match) and match.group(1) == "true"


def missing_settings(environ: dict[str, str]) -> list[str]:
    """Names of settings that the three stacks need and the shell does not provide."""
    missing = []
    if not (environ.get("AWS_PROFILE") or environ.get("AWS_ACCESS_KEY_ID")):
        missing.append("AWS_PROFILE")
    missing += [name for name in SNOWFLAKE_VARS + SNOWFLAKE_ACCOUNT_VARS if not environ.get(name)]
    return missing


def snowflake_account(environ: dict[str, str]) -> str:
    return f"{environ['SNOWFLAKE_ORGANIZATION_NAME']}-{environ['SNOWFLAKE_ACCOUNT_NAME']}"


def backend_args(environment: str, stack: str, backend_file: Path = INFRA / "backend.hcl") -> list[str]:
    text = backend_file.read_text(encoding="utf-8")
    bucket = re.search(r'^bucket\s*=\s*"([^"]+)"', text, re.MULTILINE).group(1)
    region = re.search(r'^region\s*=\s*"([^"]+)"', text, re.MULTILINE).group(1)
    return [
        f"-backend-config=bucket={bucket}",
        f"-backend-config=region={region}",
        f"-backend-config=key={environment}/{stack}/terraform.tfstate",
    ]


def terraform(stack: str, *args: str, env: dict[str, str]) -> int:
    command = ["terraform", f"-chdir={INFRA / 'stacks' / stack}", *args]
    print(f"\n$ {' '.join(command)}", flush=True)
    return subprocess.run(command, env=env, check=False).returncode


def run_stack(stack: str, environment: str, env: dict[str, str], execute: bool, allow_data_loss: bool) -> int:
    var_file = f"-var-file={tfvars_path(environment)}"
    rc = terraform(stack, "init", "-reconfigure", "-input=false", *backend_args(environment, stack), env=env)
    if rc:
        return rc

    extra = ["-var=allow_data_loss=true"] if stack == "10-platform" and allow_data_loss else []
    if not execute:
        return terraform(stack, "plan", "-destroy", "-input=false", var_file, *extra, env=env)

    if extra:
        # force_destroy is read from the state when the bucket is deleted, not from the code,
        # so the flag has to be applied before the destroy.
        rc = terraform(stack, "apply", "-auto-approve", "-input=false", var_file, *extra, env=env)
        if rc:
            return rc
    return terraform(stack, "destroy", "-auto-approve", "-input=false", var_file, *extra, env=env)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("environment", help="dev, tst, stg or prd")
    parser.add_argument("--execute", action="store_true", help="really destroy; without it only plan")
    parser.add_argument(
        "--allow-data-loss",
        action="store_true",
        help="needed when the environment file forbids deleting buckets and repositories that hold data",
    )
    args = parser.parse_args(argv)

    environment = args.environment
    if not tfvars_path(environment).exists():
        known = sorted(p.stem for p in (INFRA / "envs").glob("*.tfvars"))
        print(f"Unknown environment {environment!r}. Known: {', '.join(known)}", file=sys.stderr)
        return 2

    missing = missing_settings(os.environ)
    if missing:
        print("Set these first: " + ", ".join(missing), file=sys.stderr)
        return 2

    protected = not allows_data_loss(tfvars_path(environment).read_text(encoding="utf-8"))
    if args.execute and protected and not args.allow_data_loss:
        print(
            f"{environment} has allow_data_loss = false, so its bucket and image repository are protected.\n"
            "Pass --allow-data-loss if you really mean to delete them with their data.",
            file=sys.stderr,
        )
        return 2

    env = {
        **os.environ,
        "TF_IN_AUTOMATION": "1",
        "TF_VAR_snowflake_account": snowflake_account(os.environ),
    }

    mode = "DESTROY" if args.execute else "dry run (plan -destroy)"
    print(f"Environment {environment}: {mode}. Stacks in order: {', '.join(STACKS)}")

    if args.execute:
        answer = input(
            f"Everything of '{environment}' in AWS and Snowflake will be deleted. "
            f"Type '{environment}' to go on: "
        )
        if answer.strip() != environment:
            print("Not confirmed, nothing was changed.")
            return 1

    for stack in STACKS:
        rc = run_stack(stack, environment, env, args.execute, args.allow_data_loss)
        if rc:
            print(
                f"\nStopped: {stack} failed (exit {rc}). Fix it and run the same command again.",
                file=sys.stderr,
            )
            return rc

    if args.execute:
        print(
            f"\nEnvironment {environment} is gone. Left on purpose: bootstrap (state bucket, OIDC, "
            "CI roles), Snowflake PLATFORM_ADMIN and TERRAFORM_* users, and state files of this environment."
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
