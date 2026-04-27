#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p \
    "${SCRIPT_DIR}/data/multi-node-normal/elastic-shared/config" \
    "${SCRIPT_DIR}/data/multi-node-normal/elastic-node1/logs" \
    "${SCRIPT_DIR}/data/multi-node-normal/elastic-node2/logs" \
    "${SCRIPT_DIR}/data/multi-node-normal/kibana/"{logs,config} \
    "${SCRIPT_DIR}/data/multi-node-normal/logstash/config/conf.d"

# Minimal logstash pipeline so it can proceed past the conf.d wait loop
cat > "${SCRIPT_DIR}/data/multi-node-normal/logstash/config/conf.d/logstash.conf" << 'EOF'
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

echo "==> Starting 2-node cluster normal test..."
echo "    node1: normal disk"
echo "    node2: normal disk"
echo ""
echo "    Expected: Logstash detects disk is healthy and starts normally."
echo ""

podman compose \
    -f "${SCRIPT_DIR}/docker-compose-multi-node-normal.yml" \
    --project-name elkstack-test-multi-normal \
    up --build
