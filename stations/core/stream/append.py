#!/usr/bin/env python3
"""Commit the rows Flink just landed as a new Iceberg version."""
import json
import subprocess
import urllib.request

BASE = "http://127.0.0.1:8181"
CATALOG = "aml_history"
BUCKET = "aml-spike-lakehouse-260369602265"


def run(cmd):
    return subprocess.run(cmd, check=True, capture_output=True, text=True)


def token(client_id, client_secret):
    body = (
        "grant_type=client_credentials"
        f"&client_id={client_id}&client_secret={client_secret}&scope=PRINCIPAL_ROLE:ALL"
    ).encode()
    req = urllib.request.Request(
        BASE + "/api/catalog/v1/oauth/tokens",
        data=body,
        method="POST",
    )
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)["access_token"]


def main():
    user_token = token("root", "s3cr3t")
    copy = (
        "COPY (SELECT step, amount::float8, is_sar, alert_id "
        "FROM aml.live_payments) TO STDOUT WITH CSV HEADER"
    )
    csv_path = "/tmp/aml-live.csv"
    with open(csv_path, "w", encoding="utf-8") as handle:
        subprocess.run(
            ["psql", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", copy],
            check=True,
            stdout=handle,
        )
    from pyiceberg.catalog import load_catalog
    import pyarrow as pa
    import pyarrow.csv as pacsv

    table = pacsv.read_csv(csv_path)
    table = table.cast(
        pa.schema(
            [
                ("step", pa.int64()),
                ("amount", pa.float64()),
                ("is_sar", pa.int64()),
                ("alert_id", pa.int64()),
            ]
        )
    )
    print("live_rows", table.num_rows)
    catalog = load_catalog(
        "polaris",
        **{
            "type": "rest",
            "uri": BASE + "/api/catalog",
            "token": user_token,
            "warehouse": CATALOG,
            "s3.region": "us-west-2",
            "header.X-Iceberg-Access-Delegation": "none",
        },
    )
    iceberg = catalog.load_table(("aml", "transactions"))
    before = iceberg.current_snapshot().snapshot_id
    current_rows = iceberg.scan().to_arrow().num_rows
    print(f"ICEBERG_ROWS={current_rows}")
    if current_rows == 121457:
        iceberg.append(table)
        iceberg = catalog.load_table(("aml", "transactions"))
    elif current_rows != 121662:
        raise SystemExit(f"unexpected_iceberg_rows {current_rows}")
    after = iceberg.current_snapshot().snapshot_id
    print(f"SNAPSHOT_BEFORE={before}")
    print(f"SNAPSHOT_AFTER={after}")
    import boto3

    keys = []
    pager = boto3.client("s3", region_name="us-west-2").get_paginator("list_objects_v2")
    for page in pager.paginate(Bucket=BUCKET, Prefix="bank/"):
        for item in page.get("Contents", []):
            key = item["Key"]
            if key.endswith(".parquet") and "/metadata/" not in key:
                keys.append(key)
    data_files = sorted(keys)
    prefixes = sorted({path.rsplit("/", 1)[0] for path in data_files})
    print("parquet_prefixes", len(prefixes))
    # PXF reads one prefix. If the new files share the original directory, use it.
    # If not, use the prefix that contains the newest file.
    data_key = data_files[-1].rsplit("/", 1)[0]
    if len(prefixes) == 1:
        data_key = prefixes[0]
    psql = [
        "psql", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c",
        f"""
        DROP VIEW IF EXISTS aml.history_by_kind;
        DROP EXTERNAL TABLE IF EXISTS aml.transactions_lake CASCADE;
        CREATE EXTERNAL TABLE aml.transactions_lake (
          step bigint,
          amount float8,
          is_sar bigint,
          alert_id bigint
        ) LOCATION ('pxf://{BUCKET}/{data_key}?PROFILE=s3:parquet&SERVER=lakehouse')
        FORMAT 'CUSTOM' (FORMATTER='pxfwritable_import');
        CREATE OR REPLACE VIEW aml.history_by_kind AS
          SELECT CASE WHEN alert_id = -1 THEN 'Ordinary' ELSE 'Planted' END AS kind,
                 count(*) AS payments
          FROM aml.transactions_lake
          GROUP BY 1;
        """,
    ]
    print(run(psql).stdout)
    lake = run(["psql", "-d", "postgres", "-tA", "-c", "SELECT count(*) FROM aml.transactions_lake"]).stdout.strip()
    kinds = run(["psql", "-d", "postgres", "-c", "SELECT * FROM aml.history_by_kind ORDER BY 1"]).stdout
    print(kinds)
    print(f"LAKE_COUNT={lake}")
    if lake != "121662":
        raise SystemExit(f"lake_count {lake} != 121662")
    print("lake_grew")


if __name__ == "__main__":
    main()
