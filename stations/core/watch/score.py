#!/usr/bin/env python3
"""Run a label-blind watch, then open the planted marks and score it.

The watch looks for a ring of at least five accounts that closes within
15 simulated days. It does not see alert_id or is_sar. The marks are
opened only after the rings are named.
"""
import json
import subprocess
import urllib.error
import urllib.request
from collections import defaultdict

SUPERSET = "http://127.0.0.1:8088"


def psql(sql, check=True):
    completed = subprocess.run(
        ["psql", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", sql],
        check=False, text=True, capture_output=True,
    )
    if check and completed.returncode != 0:
        raise SystemExit(completed.stderr or completed.stdout)
    return completed


def lines(sql):
    completed = subprocess.run(
        ["psql", "-d", "postgres", "-tA", "-F", "\t", "-c", sql],
        check=True, text=True, capture_output=True,
    )
    return [line.split("\t") for line in completed.stdout.splitlines() if line]


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
        raise SystemExit(f"superset {method} {path} {exc.code} {exc.read().decode()}") from exc


def chart():
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
    created = superset("POST", "/api/v1/dataset/", {"database": db_id, "schema": "aml", "table_name": "watch_score"}, access)
    dataset_id = created["id"]
    chart_body = superset("POST", "/api/v1/chart/", {
        "slice_name": "The score, after the marks were opened",
        "viz_type": "table",
        "datasource_id": dataset_id,
        "datasource_type": "table",
        "params": json.dumps({
            "viz_type": "table",
            "query_mode": "raw",
            "all_columns": ["result", "count"],
            "datasource": f"{dataset_id}__table",
            "order_by_cols": ["[\"ord\", true]"],
            "row_limit": 10,
        }),
    }, access)
    dash = superset("POST", "/api/v1/dashboard/", {"dashboard_title": "What the watch found", "published": True}, access)
    superset("PUT", f"/api/v1/chart/{chart_body['id']}", {"dashboards": [dash["id"]]}, access)
    print(f"DASHBOARD_ID={dash['id']}")
    print(f"CHART_ID={chart_body['id']}")


def main():
    by_step = defaultdict(list)
    for orig, dest, step in lines(
        "SELECT name_orig, name_dest, step FROM aml.transactions WHERE name_orig <> name_dest"
    ):
        by_step[int(step)].append((int(orig), int(dest)))
    members = defaultdict(set)
    mains = {}
    reasons = {}
    for alert_id, reason, account_id, is_main in lines(
        "SELECT alert_id, reason, account_id, is_main FROM aml.alert_members"
    ):
        members[int(alert_id)].add(int(account_id))
        reasons[int(alert_id)] = reason
        if is_main == "t":
            mains[int(alert_id)] = int(account_id)

    found = set()
    for start in range(0, 721, 5):
        graph = defaultdict(set)
        for step in range(start, start + 15):
            for orig, dest in by_step.get(step, ()):
                graph[orig].add(dest)

        def walk(start_acct, node, path):
            if len(path) > 9:
                return
            for nxt in graph[node]:
                if nxt == start_acct and len(path) >= 5:
                    found.add(tuple(sorted(path)))
                elif nxt not in path:
                    walk(start_acct, nxt, path + (nxt,))

        for account in list(graph):
            walk(account, account, (account,))

    caught = []
    for alert_id, reason in reasons.items():
        if reason != "cycle":
            continue
        accts = members[alert_id]
        if any(set(cycle) >= accts for cycle in found):
            caught.append(alert_id)
    extra = sum(
        1 for cycle in found
        if not any(
            mains.get(alert_id) in cycle and len(set(cycle) & accts) >= 3
            for alert_id, accts in members.items()
        )
    )
    missed = sum(1 for alert_id, reason in reasons.items() if reason == "cycle" and alert_id not in caught)
    print(f"RINGS={len(found)}")
    print(f"PLANTED_RINGS_FOUND={len(caught)}")
    print(f"PLANTED_RINGS_MISSED={missed}")
    print(f"NAMED_MARKS_SAY_NO={extra}")
    if (len(found), len(caught), missed, extra) != (10183, 3, 1, 10171):
        raise SystemExit("score_unexpected")
    values = ", ".join([
        "('Planted rings found', 3, 1)",
        "('Planted rings missed', 1, 2)",
        "('Into one and Out to many, not searched for', 6, 3)",
        "('Rings the watch named', 10183, 4)",
        "('Named, and the marks say no', 10171, 5)",
    ])
    psql(f"""
        DROP TABLE IF EXISTS aml.watch_score;
        CREATE TABLE aml.watch_score (result text, count bigint, ord int);
        INSERT INTO aml.watch_score (result, count, ord) VALUES {values};
    """)
    chart()
    print("watch_scored")


if __name__ == "__main__":
    main()
