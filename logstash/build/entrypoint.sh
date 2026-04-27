#!/bin/bash

# Derive ELASTICSEARCH_URLS from DISCOVERY_SEED_HOSTS if not explicitly set
if [ -z "${ELASTICSEARCH_URLS:-}" ]; then
    if [ -n "${DISCOVERY_SEED_HOSTS:-}" ]; then
        ELASTICSEARCH_URLS=$(echo "${DISCOVERY_SEED_HOSTS}" | jq -c '[.[] | "https://" + . + ":9200"]')
        echo "Auto-derived ELASTICSEARCH_URLS from DISCOVERY_SEED_HOSTS: ${ELASTICSEARCH_URLS}"
    else
        ELASTICSEARCH_URLS='["https://elasticsearch:9200"]'
    fi
fi

until curl --insecure --silent --output /dev/null --write-out "%{http_code}" ${KIBANA_BASEURL}/login | grep -qE "200|401|403"; do
    sleep 20
    echo "Still waiting for ${KIBANA_BASEURL}..."
done
echo "${KIBANA_BASEURL} is up and running!"


CONFIG_PATH="/tmp/config"
LOGSTASH_ETC="/etc/logstash"


cd ${CONFIG_PATH}


if [ ! -f "${CONFIG_PATH}/.init_once_done" ]; then
    echo "First time setup detected."
    cp -r ${LOGSTASH_ETC}/* ${CONFIG_PATH}/
    touch "${CONFIG_PATH}/.init_once_done"
else
    echo "Configuration directory already exists. moving files to ${LOGSTASH_ETC}"
    cp -r ${CONFIG_PATH}/* ${LOGSTASH_ETC}/
fi


if [ ! -f ${LOGSTASH_ETC}/conf.d/logstash.conf ]; then
    until [ -f ${CONFIG_PATH}/conf.d/logstash.conf ]; do
        echo "Waiting for ${CONFIG_PATH}/conf.d/logstash.conf to be added..."
        sleep 20
    done
    cp ${CONFIG_PATH}/conf.d/logstash.conf ${LOGSTASH_ETC}/conf.d/logstash.conf
else
    echo "${LOGSTASH_ETC}/conf.d/logstash.conf already exists!"
fi

MONITOR_CRED_FILE="/tmp/pub-share/logstash_monitor_cred.txt"

until [ -f "${MONITOR_CRED_FILE}" ]; do
    echo "Waiting for Elasticsearch monitor credentials..."
    sleep 10
done

MONITOR_PASSWORD=$(cat "${MONITOR_CRED_FILE}")
ELASTIC_URL=$(echo "${ELASTICSEARCH_URLS}" | jq -r '.[0]')

echo "Checking Elasticsearch disk usage..."
DISK_PCT=$(curl --insecure --silent \
    -u "logstash_monitor:${MONITOR_PASSWORD}" \
    "${ELASTIC_URL}/_cat/allocation?h=disk.percent" 2>/dev/null \
    | grep -E '^[0-9]+' | sort -rn | head -1 | tr -d ' ')

if [ -z "$DISK_PCT" ]; then
    if [ "${IGNORE_DISK_CHECK:-false}" = "true" ]; then
        echo "WARNING: Could not retrieve disk usage. IGNORE_DISK_CHECK=true — proceeding anyway."
    else
        echo "ERROR: Could not retrieve disk usage from Elasticsearch. Aborting."
        echo "       Set IGNORE_DISK_CHECK=true to bypass this check (not recommended)."
        exit 1
    fi
elif [ "$DISK_PCT" -ge 90 ]; then
    if [ "${IGNORE_DISK_CHECK:-false}" = "true" ]; then
        echo "WARNING: Elasticsearch disk at ${DISK_PCT}%. IGNORE_DISK_CHECK=true — proceeding anyway."
        echo "         This risks Elasticsearch data corruption. Resolve disk pressure ASAP."
    else
        echo "ERROR: Elasticsearch disk at ${DISK_PCT}%. Refusing to start — protect data integrity."
        echo "       Free up disk space or set IGNORE_DISK_CHECK=true to bypass (not recommended)."
        exit 1
    fi
else
    echo "Elasticsearch disk usage: ${DISK_PCT}%. Proceeding."
fi

echo "Starting Logstash..."
su logstash -s /bin/bash -c "\
    /usr/share/logstash/bin/logstash \
    -f /etc/logstash/conf.d/logstash.conf \
    --path.data /var/lib/logstash \
    --path.logs /var/log/logstash \
    --log.level info \
    --api.http.host 0.0.0.0"
