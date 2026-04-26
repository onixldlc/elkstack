#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p \
    "${SCRIPT_DIR}/data/disk-limit/elastic/"{logs,config} \
    "${SCRIPT_DIR}/data/disk-limit/kibana/"{logs,config} \
    "${SCRIPT_DIR}/data/disk-limit/logstash/config"

echo "==> Starting disk-limit test stack..."
echo "    disk-filler will pre-fill a 2GB tmpfs volume to ~92% before Elasticsearch starts."
echo "    Expected: Logstash detects >90% disk usage and refuses to start."
echo ""

podman compose \
    -f "${SCRIPT_DIR}/docker-compose-disk-limit.yml" \
    --project-name elkstack-test-disk-limit \
    up --build
