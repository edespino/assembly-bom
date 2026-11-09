#!/usr/bin/env python3
"""Register the Cloudberry database, then the chapter 0 dashboard.

Chart steps look up a database named cloudberry. They do not create it.
A clean run has no connection until this step.
"""
import json
import time
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8088"
TITLE = "Practice bank, planted laundering schemes"


def call(method, path, body=None, token=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
        csrf = urllib.request.Request(BASE + "/api/v1/security/csrf_token/")
        csrf.add_header("Authorization", "Bearer " + token)
        with urllib.request.urlopen(csrf) as resp:
            req.add_header("X-CSRFToken", json.load(resp)["result"])
            cookie = resp.headers.get("Set-Cookie", "")
            if cookie:
                req.add_header("Cookie", cookie.split(";")[0])
    with urllib.request.urlopen(req) as resp:
        raw = resp.read().decode()
        return json.loads(raw) if raw else {}


def wait_health():
    for _ in range(60):
        try:
            with urllib.request.urlopen(BASE + "/health", timeout=2) as resp:
                if resp.status == 200:
                    return
        except (urllib.error.URLError, TimeoutError):
            time.sleep(2)
    raise SystemExit("superset_not_healthy")


def main():
    wait_health()
    login = call("POST", "/api/v1/security/login", {
        "username": "admin",
        "password": "admin",
        "provider": "db",
        "refresh": True,
    })
    token = login["access_token"]
    listed = call("GET", "/api/v1/database/", token=token)
    db_id = next((item["id"] for item in listed.get("result", []) if item.get("database_name") == "cloudberry"), None)
    if db_id is None:
        created = call("POST", "/api/v1/database/", {
            "database_name": "cloudberry",
            "sqlalchemy_uri": "postgresql+psycopg2://rocky@127.0.0.1:7000/postgres",
            "expose_in_sqllab": True,
            "allow_run_async": False,
        }, token)
        db_id = created["id"]
        print("database_created", db_id)
    else:
        print("database_exists", db_id)

    dashes = call("GET", "/api/v1/dashboard/", token=token)
    if any(item.get("dashboard_title") == TITLE for item in dashes.get("result", [])):
        print("chapter0_exists")
        return

    def dataset(table):
        created = call("POST", "/api/v1/dataset/", {
            "database": db_id,
            "schema": "aml",
            "table_name": table,
        }, token)
        return created["id"]

    alerts_id = dataset("alerts_by_typology")
    days_id = dataset("transactions_per_day")

    def metric(column):
        return {
            "expressionType": "SIMPLE",
            "column": {"column_name": column},
            "aggregate": "SUM",
            "label": column,
        }

    pie = call("POST", "/api/v1/chart/", {
        "slice_name": "Planted schemes by shape",
        "viz_type": "pie",
        "datasource_id": alerts_id,
        "datasource_type": "table",
        "params": json.dumps({
            "viz_type": "pie",
            "groupby": ["typology"],
            "metric": metric("alerts"),
            "datasource": f"{alerts_id}__table",
            "row_limit": 100,
        }),
    }, token)
    bar = call("POST", "/api/v1/chart/", {
        "slice_name": "Payments per simulated day",
        "viz_type": "echarts_timeseries_bar",
        "datasource_id": days_id,
        "datasource_type": "table",
        "params": json.dumps({
            "viz_type": "echarts_timeseries_bar",
            "x_axis": "day",
            "metrics": [metric("transactions")],
            "groupby": [],
            "datasource": f"{days_id}__table",
            "row_limit": 1000,
            "time_range": "No filter",
        }),
    }, token)
    dash = call("POST", "/api/v1/dashboard/", {
        "dashboard_title": TITLE,
        "published": True,
    }, token)
    dash_id = dash["id"]
    position = {
        "DASHBOARD_VERSION_KEY": "v2",
        "ROOT_ID": {"type": "ROOT", "id": "ROOT_ID", "children": ["GRID_ID"]},
        "GRID_ID": {"type": "GRID", "id": "GRID_ID", "children": ["ROW-alerts", "ROW-tx"], "parents": ["ROOT_ID"]},
        "ROW-alerts": {"type": "ROW", "id": "ROW-alerts", "children": ["CHART-alerts"], "parents": ["ROOT_ID", "GRID_ID"], "meta": {"background": "BACKGROUND_TRANSPARENT"}},
        "CHART-alerts": {"type": "CHART", "id": "CHART-alerts", "children": [], "parents": ["ROOT_ID", "GRID_ID", "ROW-alerts"], "meta": {"width": 12, "height": 50, "chartId": pie["id"], "sliceName": "Planted schemes by shape"}},
        "ROW-tx": {"type": "ROW", "id": "ROW-tx", "children": ["CHART-tx"], "parents": ["ROOT_ID", "GRID_ID"], "meta": {"background": "BACKGROUND_TRANSPARENT"}},
        "CHART-tx": {"type": "CHART", "id": "CHART-tx", "children": [], "parents": ["ROOT_ID", "GRID_ID", "ROW-tx"], "meta": {"width": 12, "height": 50, "chartId": bar["id"], "sliceName": "Payments per simulated day"}},
    }
    call("PUT", f"/api/v1/dashboard/{dash_id}", {
        "dashboard_title": TITLE,
        "published": True,
        "position_json": json.dumps(position),
    }, token)
    print(f"CHAPTER0_DASHBOARD_ID={dash_id}")


if __name__ == "__main__":
    main()
