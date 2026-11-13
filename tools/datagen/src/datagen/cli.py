"""Command line entry point: `datagen generate` and `datagen upload`."""

import argparse
import sys
from datetime import date, timedelta
from pathlib import Path

from datagen.generate import generate_day
from datagen.schemas import SCHEMAS
from datagen.storage import upload_day, write_day

DEFAULT_OUT = Path("tools/datagen/out")


def _days(start: date, count: int) -> list[date]:
    if count < 1:
        raise SystemExit("--days must be at least 1")
    return [start + timedelta(days=n) for n in range(count)]


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="datagen", description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--date", type=date.fromisoformat, required=True, help="first day, YYYY-MM-DD")
    common.add_argument("--days", type=int, default=1, help="number of consecutive days")
    common.add_argument("--out", type=Path, default=DEFAULT_OUT, help="local output directory")

    generate = sub.add_parser("generate", parents=[common], help="write Parquet partitions locally")
    generate.add_argument("--seed", type=int, default=42)
    generate.add_argument("--scale", type=float, default=1.0, help="volume multiplier")

    upload = sub.add_parser("upload", parents=[common], help="upload generated partitions to S3")
    upload.add_argument("--bucket", required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    days = _days(args.date, args.days)

    if args.command == "generate":
        for day in days:
            tables = generate_day(args.seed, day, args.scale)
            write_day(tables, args.out, day)
            counts = ", ".join(f"{name}={table.num_rows}" for name, table in tables.items())
            print(f"{day.isoformat()}: {counts}")
        return 0

    import boto3

    client = boto3.client("s3")
    for day in days:
        keys = upload_day(client, args.bucket, args.out, day, list(SCHEMAS))
        print(f"{day.isoformat()}: uploaded {len(keys)} files to s3://{args.bucket}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
