"""Writing daily partitions to disk and uploading them to S3."""

from datetime import date
from pathlib import Path
from typing import Protocol

import pyarrow as pa
import pyarrow.parquet as pq

LANDING_PREFIX = "landing"
PART_FILE = "part-0000.parquet"


class S3Uploader(Protocol):
    def upload_file(self, Filename: str, Bucket: str, Key: str) -> None: ...


def partition_key(entity: str, day: date) -> str:
    """Relative path of a partition file. Same layout locally and in the bucket."""
    return f"{LANDING_PREFIX}/{entity}/load_date={day.isoformat()}/{PART_FILE}"


def write_day(tables: dict[str, pa.Table], out_dir: Path, day: date) -> list[Path]:
    paths = []
    for entity, table in tables.items():
        path = out_dir / partition_key(entity, day)
        path.parent.mkdir(parents=True, exist_ok=True)
        pq.write_table(table, path, compression="zstd")
        paths.append(path)
    return paths


def upload_day(client: S3Uploader, bucket: str, out_dir: Path, day: date, entities: list[str]) -> list[str]:
    """Upload the partition files of one day. Fails before uploading if any file is missing."""
    keys = [partition_key(entity, day) for entity in entities]
    missing = [key for key in keys if not (out_dir / key).is_file()]
    if missing:
        raise FileNotFoundError(f"not generated yet: {', '.join(missing)}")

    for key in keys:
        client.upload_file(Filename=str(out_dir / key), Bucket=bucket, Key=key)
    return keys
