#!/usr/bin/env bash
set -euo pipefail
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "stream" ]]; then
  echo "[stream-land] ERROR: this step is stream-only" >&2
  exit 1
fi
# shellcheck disable=SC1091
source /usr/local/cloudberry/cloudberry-env.sh
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$script_dir/../../../lib/gpdemo-env.sh"
demo=$(gpdemo_env_file) || {
  echo "[stream-land] ERROR: gpdemo-env.sh not found at ${HOME}/gpdemo/gpdemo-env.sh" >&2
  exit 1
}
# shellcheck disable=SC1090
source "$demo"

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
lib=$(find "$HOME/bom-parts/flink" -type d -path '*/flink-dist/target/flink-*-bin/flink-*/lib' | head -1)
clients=$(find "$HOME/bom-parts/kafka" -type f -path '*/clients/build/libs/kafka-clients-*.jar' | head -1)
producer=$(find "$HOME/bom-parts/kafka" -type f -name 'kafka-console-producer.sh' | head -1)
topics=$(find "$HOME/bom-parts/kafka" -type f -name 'kafka-topics.sh' | head -1)
if [[ -z "$lib" || -z "$clients" || -z "$producer" || -z "$topics" ]]; then
  echo "[stream-land] ERROR: flink or kafka tools missing" >&2
  exit 1
fi

jdbc_jar=/tmp/postgresql-42.7.7.jar
if [[ ! -f "$jdbc_jar" ]]; then
  curl -fsSL -o "$jdbc_jar" https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.7/postgresql-42.7.7.jar
fi
echo "157963d60ae66d607e09466e8c0cdf8087e9cb20d0159899ffca96bca2528460  $jdbc_jar" | sha256sum -c -

export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export PATH="${JAVA_HOME}/bin:${PATH}"
cp=$(find "$lib" -name '*.jar' -printf '%p:')
cp="${cp}${clients}:${jdbc_jar}"
javac -cp "$cp" -d /tmp/live-landing "$script_dir/LiveLanding.java"

psql -d postgres -v ON_ERROR_STOP=1 -c "
CREATE TABLE IF NOT EXISTS aml.live_payments (
  step bigint,
  amount float8,
  is_sar bigint,
  alert_id bigint
);
TRUNCATE aml.live_payments;
"

"$topics" --bootstrap-server 127.0.0.1:9092 --create --if-not-exists --topic payments --partitions 1 --replication-factor 1
{
  for i in $(seq 1 200); do
    echo "1,10.0,0,-1"
  done
  echo "145,500.0,1,6"
  echo "146,500.0,1,6"
  echo "148,500.0,1,6"
  echo "152,500.0,1,6"
  echo "155,500.0,1,6"
} | "$producer" --bootstrap-server 127.0.0.1:9092 --topic payments

java -cp "/tmp/live-landing:$cp" LiveLanding 127.0.0.1:9092 payments \
  "jdbc:postgresql://127.0.0.1:${PGPORT}/postgres?user=${USER}" 205

live=$(psql -d postgres -tA -c "SELECT count(*) FROM aml.live_payments")
echo "LIVE_COUNT=$live"
if [[ "$live" != "205" ]]; then
  echo "[stream-land] ERROR: expected 205 landed rows, got $live" >&2
  exit 1
fi

if ! python3.11 -m pip --version >/dev/null 2>&1; then
  sudo dnf install -y python3.11 python3.11-pip
fi
python3.11 -m pip install --user 'pyiceberg==0.12.0' 'pyarrow' 'boto3'
python3.11 "$script_dir/append.py"
echo "[stream-land] RESULT: PASS"
