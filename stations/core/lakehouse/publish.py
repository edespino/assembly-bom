#!/usr/bin/env python3
"""Publish the bank history as Iceberg under Polaris, then a Cloudberry read in place."""
import json
import os
import subprocess
import urllib.error
import urllib.request

BUCKET = "aml-spike-lakehouse-260369602265"
LAKE_PREFIX = os.environ.get("LAKE_PREFIX", "").strip().strip("/")
if not LAKE_PREFIX or "/" in LAKE_PREFIX:
    raise SystemExit("LAKE_PREFIX must be one path segment")
PREFIX = f"{LAKE_PREFIX}/transactions"
CATALOG = "aml_history"
REALM = "POLARIS"
BASE = "http://127.0.0.1:8181"
SUPERSET = "http://127.0.0.1:8088"


def run(cmd, **kwargs):
    completed = subprocess.run(cmd, check=False, text=True, capture_output=True, **kwargs)
    if completed.returncode != 0:
        raise SystemExit(completed.stderr or completed.stdout or f"exit {completed.returncode}")
    return completed


def http(method, url, body=None, headers=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method)
    for key, value in (headers or {}).items():
        req.add_header(key, value)
    if body is not None:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req) as resp:
        raw = resp.read().decode()
        return json.loads(raw) if raw else {}


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


def post_ok(path, body, headers):
    try:
        return http("POST", BASE + path, body, headers)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode()
        if exc.code in (409, 400) and "already" in detail.lower():
            return None
        raise SystemExit(f"post_failed {exc.code} {path} {detail}")


def role_arn():
    arn = run(["aws", "sts", "get-caller-identity", "--query", "Arn", "--output", "text"]).stdout.strip()
    # arn:aws:sts::ACCOUNT:assumed-role/ROLE/session
    role = arn.split(":assumed-role/")[1].split("/")[0]
    account = arn.split(":")[4]
    return f"arn:aws:iam::{account}:role/{role}"


def main():
    root = token("root", "s3cr3t")
    headers = {
        "Authorization": "Bearer " + root,
        "Polaris-Realm": REALM,
        "Accept": "application/json",
    }
    existing = None
    try:
        existing = http("GET", BASE + f"/api/management/v1/catalogs/{CATALOG}", None, headers)
    except urllib.error.HTTPError as exc:
        exc.read()
        if exc.code != 404:
            raise
    listed = run(["aws", "s3", "ls", f"s3://{BUCKET}/{LAKE_PREFIX}/", "--recursive"]).stdout
    if any(line.endswith(".parquet") and "/metadata/" not in line for line in listed.splitlines()):
        raise SystemExit(f"lake_prefix_already_has_files {LAKE_PREFIX}")
    location = f"s3://{BUCKET}/{LAKE_PREFIX}"
    storage = {
        "storageType": "S3",
        "roleArn": role_arn(),
        "region": "us-west-2",
        "allowedLocations": [f"s3://{BUCKET}/"],
        "stsUnavailable": True,
        "kmsUnavailable": True,
    }
    if existing is None:
        payload = {
            "catalog": {
                "name": CATALOG,
                "type": "INTERNAL",
                "readOnly": False,
                "properties": {"default-base-location": location},
                "storageConfigInfo": storage,
            }
        }
        try:
            http("POST", BASE + "/api/management/v1/catalogs", payload, headers)
            print("catalog_created")
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode()
            raise SystemExit(f"catalog_create_failed {exc.code} {detail}")
    else:
        updated = http(
            "PUT",
            BASE + f"/api/management/v1/catalogs/{CATALOG}",
            {
                "currentEntityVersion": existing["entityVersion"],
                "properties": {"default-base-location": location},
                "storageConfigInfo": storage,
            },
            headers,
        )
        print("catalog_updated", updated.get("entityVersion"))

    home = os.path.expanduser("~/polaris-run")
    os.makedirs(home, exist_ok=True)
    cred_path = os.path.join(home, "client.env")
    try:
        principal = http(
            "POST",
            BASE + "/api/management/v1/principals",
            {"principal": {"name": "lakehouse_user", "properties": {}}},
            headers,
        )
        client_id = principal["credentials"]["clientId"]
        client_secret = principal["credentials"]["clientSecret"]
        with open(cred_path, "w", encoding="utf-8") as handle:
            handle.write(f"CLIENT_ID={client_id}\nCLIENT_SECRET={client_secret}\n")
        os.chmod(cred_path, 0o600)
        print("principal_created")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode()
        if exc.code not in (409, 400) or not os.path.exists(cred_path):
            raise SystemExit(f"principal_failed {exc.code} {detail}")
        saved = {}
        for line in open(cred_path, encoding="utf-8"):
            key, value = line.strip().split("=", 1)
            saved[key] = value
        client_id = saved["CLIENT_ID"]
        client_secret = saved["CLIENT_SECRET"]
        print("principal_exists")

    def ignore_exists(method, path, body):
        try:
            return http(method, BASE + path, body, headers)
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode()
            if exc.code in (409, 400) and "already" in detail.lower():
                return None
            raise SystemExit(f"setup_failed {exc.code} {path} {detail}")

    ignore_exists("POST", "/api/management/v1/principal-roles", {"principalRole": {"name": "lakehouse_user_role", "properties": {}}})
    ignore_exists("PUT", "/api/management/v1/principals/lakehouse_user/principal-roles", {"principalRole": {"name": "lakehouse_user_role"}})
    ignore_exists("POST", f"/api/management/v1/catalogs/{CATALOG}/catalog-roles", {"catalogRole": {"name": "lakehouse_catalog_role", "properties": {}}})
    ignore_exists("PUT", f"/api/management/v1/principal-roles/lakehouse_user_role/catalog-roles/{CATALOG}", {"catalogRole": {"name": "lakehouse_catalog_role"}})
    ignore_exists("PUT", f"/api/management/v1/catalogs/{CATALOG}/catalog-roles/lakehouse_catalog_role/grants", {"type": "catalog", "privilege": "CATALOG_MANAGE_CONTENT"})
    print("grants_ok")

    user_token = token(client_id, client_secret)
    from pyiceberg.catalog import load_catalog
    import pyarrow as pa
    import pyarrow.csv as pacsv

    csv_path = "/tmp/aml-transactions.csv"
    copy = (
        "COPY (SELECT step, amount::float8, is_sar, alert_id "
        "FROM aml.transactions) TO STDOUT WITH CSV HEADER"
    )
    with open(csv_path, "w", encoding="utf-8") as handle:
        subprocess.run(
            ["psql", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", copy],
            check=True,
            stdout=handle,
        )
    table = pacsv.read_csv(csv_path)
    print("exported_rows", table.num_rows)

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
    try:
        catalog.create_namespace("aml")
    except Exception as exc:
        if "AlreadyExists" not in type(exc).__name__ and "already exists" not in str(exc).lower():
            raise
    schema = table.schema
    try:
        iceberg = catalog.create_table(("aml", "transactions"), schema=schema)
    except Exception as exc:
        if "AlreadyExists" not in type(exc).__name__ and "already exists" not in str(exc).lower():
            raise
        iceberg = catalog.load_table(("aml", "transactions"))
    if iceberg.current_snapshot() is None:
        iceberg.append(table)
        print("iceberg_appended")
    else:
        print("iceberg_already_loaded")
    listed = run(["aws", "s3", "ls", f"s3://{BUCKET}/{LAKE_PREFIX}/", "--recursive"]).stdout
    data_files = [
        line.split()[-1]
        for line in listed.splitlines()
        if line.endswith(".parquet") and "/metadata/" not in line
    ]
    if not data_files:
        raise SystemExit("no_parquet")
    data_key = data_files[0].rsplit("/", 1)[0]
    print("parquet_prefix", data_key)

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
    heap = run(["psql", "-d", "postgres", "-tA", "-c", "SELECT count(*) FROM aml.transactions"]).stdout.strip()
    lake = run(["psql", "-d", "postgres", "-tA", "-c", "SELECT count(*) FROM aml.transactions_lake"]).stdout.strip()
    print(f"HEAP_COUNT={heap}")
    print(f"LAKE_COUNT={lake}")
    if heap != lake:
        raise SystemExit("count_mismatch")
    print("counts_match")
    add_chart()


def superset(method, path, body, token_value):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(SUPERSET + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", "Bearer " + token_value)
    csrf_req = urllib.request.Request(SUPERSET + "/api/v1/security/csrf_token/")
    csrf_req.add_header("Authorization", "Bearer " + token_value)
    with urllib.request.urlopen(csrf_req) as csrf_resp:
        req.add_header("X-CSRFToken", json.load(csrf_resp)["result"])
        cookie = csrf_resp.headers.get("Set-Cookie", "")
        if cookie:
            req.add_header("Cookie", cookie.split(";")[0])
    with urllib.request.urlopen(req) as resp:
        raw = resp.read().decode()
        return json.loads(raw) if raw else {}


def add_chart():
    req = urllib.request.Request(
        SUPERSET + "/api/v1/security/login",
        data=json.dumps({
            "username": "admin",
            "password": "admin",
            "provider": "db",
            "refresh": True,
        }).encode(),
        method="POST",
    )
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req) as resp:
        access = json.load(resp)["access_token"]
    listed = superset("GET", "/api/v1/database/", None, access)
    db_id = None
    for item in listed.get("result", []):
        if item.get("database_name") == "cloudberry":
            db_id = item["id"]
            break
    if db_id is None:
        raise SystemExit("superset_database_missing")
    created = superset("POST", "/api/v1/dataset/", {
        "database": db_id,
        "schema": "aml",
        "table_name": "history_by_kind",
    }, access)
    dataset_id = created["id"]
    chart = superset("POST", "/api/v1/chart/", {
        "slice_name": "Planted and ordinary, from the history files",
        "viz_type": "table",
        "datasource_id": dataset_id,
        "datasource_type": "table",
        "params": json.dumps({
            "viz_type": "table",
            "query_mode": "raw",
            "all_columns": ["kind", "payments"],
            "datasource": f"{dataset_id}__table",
            "row_limit": 10,
        }),
    }, access)
    chart_id = chart["id"]
    dash = superset("POST", "/api/v1/dashboard/", {
        "dashboard_title": "History, where it sits",
        "published": True,
    }, access)
    dash_id = dash["id"]
    superset("PUT", f"/api/v1/chart/{chart_id}", {"dashboards": [dash_id]}, access)
    print(f"DASHBOARD_ID={dash_id}")
    print(f"CHART_ID={chart_id}")


if __name__ == "__main__":
    main()
