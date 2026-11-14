"""Container entrypoint: run dbt, then keep the run artifacts.

    entrypoint.py build --target runtime        # arguments go to dbt unchanged

The exit code is always the one dbt returned. Uploading artifacts is best effort: a failed
upload is logged but never turns a green run red, and never hides a red one.

Environment:
    ARTIFACT_BUCKET   lake bucket. Without it nothing is uploaded (local runs).
    DBT_ENV           environment name, used in the object key.
    RUN_ID            identifies the run. Set by the orchestrator, otherwise generated.
"""

from __future__ import annotations

import os
import subprocess
import sys
import uuid
from datetime import UTC, datetime
from pathlib import Path

ARTIFACTS = ("run_results.json", "manifest.json")


def run_dbt(args: list[str]) -> int:
    return subprocess.run(["dbt", *args], check=False).returncode


def upload(target_dir: Path, bucket: str, environment: str, run_id: str, succeeded: bool) -> None:
    import boto3  # imported late so `dbt` itself never depends on it

    s3 = boto3.client("s3")
    base = f"artifacts/dbt/{environment}"
    for name in ARTIFACTS:
        path = target_dir / name
        if not path.is_file():
            print(f"entrypoint: {name} not produced, skipping", flush=True)
            continue
        keys = [f"{base}/{run_id}/{name}"]
        # `latest` is what the next run compares against for state-based selection, so only a
        # successful run may move it.
        if succeeded and name == "manifest.json":
            keys.append(f"{base}/latest/{name}")
        for key in keys:
            s3.upload_file(str(path), bucket, key)
            print(f"entrypoint: uploaded s3://{bucket}/{key}", flush=True)


def check_writable(path: Path) -> bool:
    """dbt exits silently when it cannot create its target directory, so say why up front."""
    try:
        path.mkdir(parents=True, exist_ok=True)
        probe = path / ".probe"
        probe.touch()
        probe.unlink()
    except OSError as exc:
        parent = path.parent if path.parent.exists() else Path("/")
        st = parent.stat()
        print(
            f"entrypoint: cannot write to {path}: {exc}; uid={os.getuid()}, "
            f"{parent} is owned by {st.st_uid} with mode {oct(st.st_mode & 0o7777)}",
            file=sys.stderr,
            flush=True,
        )
        return False
    return True


def main() -> int:
    if not check_writable(Path(os.environ.get("DBT_TARGET_PATH", "target"))):
        return 1
    code = run_dbt(sys.argv[1:])

    bucket = os.environ.get("ARTIFACT_BUCKET")
    if bucket:
        environment = os.environ.get("DBT_ENV", "unknown")
        run_id = os.environ.get("RUN_ID") or (
            datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
        )
        target_dir = Path(os.environ.get("DBT_TARGET_PATH", "target"))
        try:
            upload(target_dir, bucket, environment, run_id, succeeded=code == 0)
        except Exception as exc:
            print(f"entrypoint: artifact upload failed: {exc!r}", file=sys.stderr, flush=True)

    return code


if __name__ == "__main__":
    sys.exit(main())
