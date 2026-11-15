"""Everything an environment-agnostic DAG needs to know about where it runs.

The only input is PLATFORM_ENV. Names and ARNs are read from the SSM document the platform
stack publishes, so no DAG file mentions a resource.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

PROJECT = "dataplat"
DDL_DIR = Path(__file__).resolve().parents[1] / "sql" / "ddl"


def environment() -> str:
    """Name of the environment this Airflow drives, e.g. dev."""
    return os.environ["PLATFORM_ENV"].lower()


def entities() -> list[str]:
    """Landing entities, one per DDL file, so a new table needs no change in the DAG."""
    return sorted(path.stem for path in DDL_DIR.glob("*.sql"))


def ddl(entity: str) -> str:
    return (DDL_DIR / f"{entity}.sql").read_text(encoding="utf-8")


def load_platform_config(ssm=None) -> dict:
    """Read the platform document of this environment from SSM Parameter Store."""
    if ssm is None:
        import boto3

        ssm = boto3.client("ssm")
    name = f"/{PROJECT}/{environment()}/platform/config"
    return json.loads(ssm.get_parameter(Name=name)["Parameter"]["Value"])
