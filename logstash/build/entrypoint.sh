#/bin/bash


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
ELASTIC_URL=$(echo "${ELASTICSEARCH_URLS:-[\"https://elasticsearch:9200\"]}" | jq -r '.[0]')

echo "Checking Elasticsearch disk usage..."
DISK_PCT=$(curl --insecure --silent \
    -u "logstash_monitor:${MONITOR_PASSWORD}" \
    "${ELASTIC_URL}/_cat/allocation?h=disk.percent" 2>/dev/null \
    | grep -E '^[0-9]+' | sort -rn | head -1 | tr -d ' ')

if [ -z "$DISK_PCT" ]; then
    echo "ERROR: Could not retrieve disk usage from Elasticsearch. Aborting."
    exit 1
elif [ "$DISK_PCT" -ge 90 ]; then
    echo "ERROR: Elasticsearch disk at ${DISK_PCT}%. Refusing to start — protect data integrity."
    exit 1
else
    echo "Elasticsearch disk usage: ${DISK_PCT}%. Proceeding."
fi

echo "Starting Logstash..."
su logstash -s /bin/bash -c "\
    /usr/share/logstash/bin/logstash -f /etc/logstash/conf.d/logstash.conf 
    --path.data /var/lib/logstash \
    --path.logs /var/log/logstash \
    --log.level info \
    --http.host"