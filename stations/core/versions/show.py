#!/usr/bin/env python3
"""Ask the file table for the version before the new payments, and the latest."""
import json
import subprocess
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8181"
CATALOG = "aml_history"
SUPERSET = "http://127.0.0.1:8088"
BEFORE = "Before the new payments"
AFTER = "After the new payments"


def run(cmd):
    completed = subprocess.run(cmd, check=False, text=True, capture_output=True)
    if completed.returncode != 0:
        raise SystemExit(completed.stderr or completed.stdout or f"exit {completed.returncode}")
    return completed


def token(client_id, client_secret):
    body = (
        "grant_type=client_credentials"
        f"&client_id={client_id}&client_secret={client_secret}&scope=PRINCIPAL_ROLE:ALL"
    ).encode()
    req = urllib.request.Request(BASE + "/api/catalog/v1/oauth/tokens", data=body, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)["access_token"]


def counts(iceberg, snapshot_id):
    arrow = iceberg.scan(snapshot_id=snapshot_id).to_arrow()
    alert = arrow.column("alert_id").to_pylist()
    planted = sum(1 for value in alert if value != -1)
    ordinary = len(alert) - planted
    return ordinary, planted, len(alert)


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
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read().decode()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode()
        raise SystemExit(f"superset {method} {path} {exc.code} {detail}") from exc


def chart(rows):
    req = urllib.request.Request(
        SUPERSET + "/api/v1/security/login",
        data=json.dumps({"username": "admin", "password": "admin", "provider": "db", "refresh": True}).encode(),
        method="POST",
    )
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req) as resp:
        access = json.load(resp)["access_token"]
    listed = superset("GET", "/api/v1/database/", None, access)
    db_id = next(item["id"] for item in listed.get("result", []) if item.get("database_name") == "cloudberry")
    created = superset("POST", "/api/v1/dataset/", {"database": db_id, "schema": "aml", "table_name": "history_at_version"}, access)
    dataset_id = created["id"]
    chart_body = superset("POST", "/api/v1/chart/", {
        "slice_name": "Before and after, from the files",
        "viz_type": "table",
        "datasource_id": dataset_id,
        "datasource_type": "table",
        "params": json.dumps({
            "viz_type": "table",
            "query_mode": "raw",
            "all_columns": ["version", "kind", "payments"],
            "datasource": f"{dataset_id}__table",
            "row_limit": 10,
        }),
    }, access)
    dash = superset("POST", "/api/v1/dashboard/", {"dashboard_title": "What the files had", "published": True}, access)
    superset("PUT", f"/api/v1/chart/{chart_body['id']}", {"dashboards": [dash["id"]]}, access)
    print(f"DASHBOARD_ID={dash['id']}")
    print(f"CHART_ID={chart_body['id']}")


def main():
    user_token = token("root", "s3cr3t")
    from pyiceberg.catalog import load_catalog

    catalog = load_catalog("polaris", **{
        "type": "rest",
        "uri": BASE + "/api/catalog",
        "token": user_token,
        "warehouse": CATALOG,
        "s3.region": "us-west-2",
        "header.X-Iceberg-Access-Delegation": "none",
    })
    iceberg = catalog.load_table(("aml", "transactions"))
    current = iceberg.current_snapshot()
    parent_id = current.parent_snapshot_id
    if parent_id is None:
        raise SystemExit("no_earlier_version")
    before = counts(iceberg, parent_id)
    after = counts(iceberg, current.snapshot_id)
    print(f"BEFORE_ID={parent_id}")
    print(f"AFTER_ID={current.snapshot_id}")
    print(f"BEFORE ordinary={before[0]} planted={before[1]} total={before[2]}")
    print(f"AFTER ordinary={after[0]} planted={after[1]} total={after[2]}")
    if before != (121392, 65, 121457) or after != (121592, 70, 121662):
        raise SystemExit("version_counts_unexpected")
    values = ", ".join(
        f"('{version}', '{kind}', {payments})"
        for version, pair in ((BEFORE, before), (AFTER, after))
        for kind, payments in (("Ordinary", pair[0]), ("Planted", pair[1]))
    )
    run(["psql", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", f"""
        DROP TABLE IF EXISTS aml.history_at_version;
        CREATE TABLE aml.history_at_version (
          version text,
          kind text,
          payments bigint
        );
        INSERT INTO aml.history_at_version (version, kind, payments) VALUES {values};
    """])
    chart(((BEFORE, before), (AFTER, after)))
    print("versions_shown")


if __name__ == "__main__":
    main()
