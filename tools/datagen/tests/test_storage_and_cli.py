import hashlib
from datetime import date

import pyarrow.parquet as pq
import pytest

from datagen import cli
from datagen.generate import generate_day
from datagen.schemas import SCHEMAS
from datagen.storage import partition_key, upload_day, write_day

DAY = date(2025, 3, 15)


class FakeS3:
    def __init__(self):
        self.calls = []

    def upload_file(self, Filename, Bucket, Key):
        self.calls.append((Filename, Bucket, Key))


def _digests(root):
    return {
        p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(root.rglob("*.parquet"))
    }


def test_partition_key_layout():
    assert partition_key("orders", DAY) == "landing/orders/load_date=2025-03-15/part-0000.parquet"


def test_write_day_round_trips(tmp_path):
    tables = generate_day(1, DAY, 0.1)
    paths = write_day(tables, tmp_path, DAY)

    assert len(paths) == len(SCHEMAS)
    for entity, table in tables.items():
        assert pq.read_table(tmp_path / partition_key(entity, DAY)).equals(table)


def test_generated_files_are_byte_identical_between_runs(tmp_path):
    for run in ("a", "b"):
        assert cli.main(["generate", "--date", "2025-03-15", "--days", "2", "--scale", "0.1",
                         "--out", str(tmp_path / run)]) == 0  # fmt: skip

    first, second = _digests(tmp_path / "a"), _digests(tmp_path / "b")
    assert len(first) == 2 * len(SCHEMAS)
    assert first == second


def test_upload_day_uses_same_keys_as_local_layout(tmp_path):
    write_day(generate_day(1, DAY, 0.1), tmp_path, DAY)
    client = FakeS3()

    keys = upload_day(client, "bucket", tmp_path, DAY, list(SCHEMAS))

    assert keys == [partition_key(entity, DAY) for entity in SCHEMAS]
    assert [(bucket, key) for _, bucket, key in client.calls] == [("bucket", key) for key in keys]


def test_upload_day_uploads_nothing_when_a_file_is_missing(tmp_path):
    write_day(generate_day(1, DAY, 0.1), tmp_path, DAY)
    (tmp_path / partition_key("payments", DAY)).unlink()
    client = FakeS3()

    with pytest.raises(FileNotFoundError, match="payments"):
        upload_day(client, "bucket", tmp_path, DAY, list(SCHEMAS))
    assert client.calls == []


def test_cli_rejects_non_positive_days(tmp_path):
    with pytest.raises(SystemExit):
        cli.main(["generate", "--date", "2025-03-15", "--days", "0", "--out", str(tmp_path)])
