#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p \
    "${SCRIPT_DIR}/data/normal/elastic/"{data,logs,config} \
    "${SCRIPT_DIR}/data/normal/kibana/"{logs,config} \
    "${SCRIPT_DIR}/data/normal/logstash/config"

echo "==> Starting normal test stack (all services should come up healthy)..."
podman compose \
    -f "${SCRIPT_DIR}/docker-compose-normal.yml" \
    --project-name elkstack-test-normal \
    up --build
