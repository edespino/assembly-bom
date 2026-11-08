#!/usr/bin/env bash
set -euo pipefail
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "pxf" ]]; then
  echo "[pxf-prepare] ERROR: this step is pxf-only" >&2
  exit 1
fi
# shellcheck disable=SC1091
source /usr/local/cloudberry/cloudberry-env.sh
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
export PATH="${JAVA_HOME}/bin:${PXF_HOME:-/usr/local/cloudberry-pxf}/bin:${PATH}"
export PXF_HOME=/usr/local/cloudberry-pxf
export PXF_BASE="${HOME}/pxf-base"
pxf prepare
server="$PXF_BASE/servers/lakehouse"
mkdir -p "$server"
cat > "$server/s3-site.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <property>
    <name>fs.s3a.aws.credentials.provider</name>
    <value>com.amazonaws.auth.InstanceProfileCredentialsProvider</value>
  </property>
  <property>
    <name>fs.s3a.endpoint.region</name>
    <value>us-west-2</value>
  </property>
</configuration>
EOF
echo "[pxf-prepare] RESULT: PASS"
