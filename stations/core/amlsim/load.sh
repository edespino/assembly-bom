#!/usr/bin/env bash
set -euo pipefail
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "amlsim" ]]; then
  echo "[amlsim-load] ERROR: this step is amlsim-only" >&2
  exit 1
fi
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
tree="$PARTS_DIR/$NAME"
accounts="$tree/tmp/sample/accounts.csv"
alerts="$tree/tmp/sample/alert_members.csv"
tx_log="$tree/outputs/sample/tx_log.csv"
tx_count="$tree/outputs/sample/tx_count.csv"
for f in "$accounts" "$alerts" "$tx_log" "$tx_count"; do
  if [[ ! -s "$f" ]]; then
    echo "[amlsim-load] ERROR: missing $f" >&2
    exit 1
  fi
done

# shellcheck disable=SC1091
source /usr/local/cloudberry/cloudberry-env.sh
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$script_dir/../../../lib/gpdemo-env.sh"
demo_env=$(gpdemo_env_file) || {
  echo "[amlsim-load] ERROR: gpdemo-env.sh not found at ${HOME}/gpdemo/gpdemo-env.sh" >&2
  exit 1
}
# shellcheck disable=SC1090
source "$demo_env"

psql -d postgres -v ON_ERROR_STOP=1 <<SQL
CREATE SCHEMA IF NOT EXISTS aml;
DROP TABLE IF EXISTS aml.transactions, aml.tx_count, aml.alert_members, aml.accounts CASCADE;
CREATE TABLE aml.accounts (
  account_id int,
  customer_id text,
  init_balance numeric,
  country text,
  account_type text,
  is_sar boolean,
  bank_id text
);
CREATE TABLE aml.alert_members (
  alert_id int,
  reason text,
  account_id int,
  is_main boolean,
  is_sar boolean,
  model_id int,
  min_amount numeric,
  max_amount numeric,
  start_step int,
  end_step int,
  schedule_id int,
  bank_id text
);
CREATE TABLE aml.transactions (
  step int,
  tx_type text,
  amount numeric,
  name_orig int,
  oldbalance_orig numeric,
  newbalance_orig numeric,
  name_dest int,
  oldbalance_dest numeric,
  newbalance_dest numeric,
  is_sar int,
  alert_id int
);
CREATE TABLE aml.tx_count (
  step int,
  normal int,
  sar int
);
SQL

psql -d postgres -v ON_ERROR_STOP=1 -c "\\copy aml.accounts FROM '$accounts' WITH (FORMAT csv, HEADER true)"
psql -d postgres -v ON_ERROR_STOP=1 -c "\\copy aml.alert_members FROM '$alerts' WITH (FORMAT csv, HEADER true)"
psql -d postgres -v ON_ERROR_STOP=1 -c "\\copy aml.transactions FROM '$tx_log' WITH (FORMAT csv, HEADER true)"
psql -d postgres -v ON_ERROR_STOP=1 -c "\\copy aml.tx_count FROM '$tx_count' WITH (FORMAT csv, HEADER true)"

psql -d postgres -v ON_ERROR_STOP=1 <<'SQL'
CREATE OR REPLACE VIEW aml.alerts_by_typology AS
  SELECT CASE reason
    WHEN 'fan_in' THEN 'Into one'
    WHEN 'fan_out' THEN 'Out to many'
    WHEN 'cycle' THEN 'Comes back'
    ELSE reason
  END AS typology,
  count(DISTINCT alert_id) AS alerts,
  count(*) AS members
  FROM aml.alert_members
  GROUP BY 1;
CREATE OR REPLACE VIEW aml.transactions_per_day AS
  SELECT step AS day, normal, sar, normal + sar AS transactions
  FROM aml.tx_count
  ORDER BY step;
SQL

psql -d postgres -c 'SELECT count(*) AS accounts FROM aml.accounts; SELECT count(*) AS transactions FROM aml.transactions; SELECT typology, alerts FROM aml.alerts_by_typology ORDER BY alerts DESC;'
echo "[amlsim-load] RESULT: PASS"
