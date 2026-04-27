#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p \
    "${SCRIPT_DIR}/data/multi-node/elastic-shared/config" \
    "${SCRIPT_DIR}/data/multi-node/elastic-node1/logs" \
    "${SCRIPT_DIR}/data/multi-node/elastic-node2/logs" \
    "${SCRIPT_DIR}/data/multi-node/kibana/"{logs,config} \
    "${SCRIPT_DIR}/data/multi-node/logstash/config/conf.d"

# Minimal logstash pipeline so it can proceed past the conf.d wait loop
cat > "${SCRIPT_DIR}/data/multi-node/logstash/config/conf.d/logstash.conf" << 'EOF'
input {
  heartbeat {
    interval => 60
    message => "test"
  }
}
output {
  stdout { codec => rubydebug }
}
EOF

echo "==> Starting 2-node cluster test..."
echo "    node1: normal disk"
echo "    node2: tmpfs pre-filled to ~92%"
echo ""
echo "    Expected: Logstash detects a node at >= 90% and refuses to start."
echo "    To bypass: uncomment IGNORE_DISK_CHECK=true in docker-compose-multi-node.yml"
echo ""

podman compose \
    -f "${SCRIPT_DIR}/docker-compose-multi-node.yml" \
    --project-name elkstack-test-multi \
    up --build
