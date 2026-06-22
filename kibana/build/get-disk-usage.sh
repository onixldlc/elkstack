#!/bin/bash
# Outputs: DISK_PCT WATERMARK_PCT
# Requires env: ELASTICSEARCH_URLS (JSON array), ES_AUTH_USER, ES_AUTH_PASS

ELASTIC_URL=$(echo "${ELASTICSEARCH_URLS}" | jq -r '.[0]')
AUTH_USER="${ES_AUTH_USER:-elastic}"
AUTH_PASS="${ES_AUTH_PASS}"

WATERMARK_RAW=$(curl --insecure --silent \
    -u "${AUTH_USER}:${AUTH_PASS}" \
    "${ELASTIC_URL}/_cluster/settings?include_defaults=true&flat_settings=true" 2>/dev/null \
    | jq -r '
        .transient["cluster.routing.allocation.disk.watermark.flood_stage"] //
        .persistent["cluster.routing.allocation.disk.watermark.flood_stage"] //
        .defaults["cluster.routing.allocation.disk.watermark.flood_stage"] //
        empty
    ')

WATERMARK_PCT=$(echo "${WATERMARK_RAW}" | grep -oE '[0-9]+' | head -1)

DISK_PCT=$(curl --insecure --silent \
    -u "${AUTH_USER}:${AUTH_PASS}" \
    "${ELASTIC_URL}/_cat/allocation?h=disk.percent" 2>/dev/null \
    | grep -E '^[0-9]+' | sort -rn | head -1 | tr -d ' ')

echo "${DISK_PCT:-} ${WATERMARK_PCT:-}"
