#!/bin/bash

CONFIG_PATH="/tmp/config"
SHARE_PATH="/tmp/share"
ELASTIC_SHARE="/usr/share/elasticsearch"
ELASTIC_ETC="/etc/elasticsearch"
ELASTIC_BUILD="/elastic"
ELASTIC_LOG="/var/log/elasticsearch"
ELASTIC_LIB="/var/lib/elasticsearch"
mkdir -p ${CONFIG_PATH}
mkdir -p ${SHARE_PATH}

if [ -f ${SHARE_PATH}/credential.txt ]; then
    RANDOM_PASSWORD=$(cat ${SHARE_PATH}/credential.txt)
else
    RANDOM_PASSWORD=$(< /dev/urandom tr -dc 'A-Za-z0-9' | head -c 8)
fi

PASSWORD=${ELASTIC_PASSWORD:-$RANDOM_PASSWORD}

# Atomic leader election for shared-config init (multi-node safe).
# Stale lock from a crashed prior run is cleared if .init_complete already exists.
if [ -f ${CONFIG_PATH}/.init_complete ]; then
    rmdir ${CONFIG_PATH}/.init_lock 2>/dev/null
    INIT_LEADER=0
elif mkdir ${CONFIG_PATH}/.init_lock 2>/dev/null; then
    INIT_LEADER=1
else
    echo "Another node is performing first-time init. Waiting..."
    until [ -f ${CONFIG_PATH}/.init_complete ]; do
        sleep 2
    done
    INIT_LEADER=0
fi

if [ "$INIT_LEADER" = "1" ]; then
    if [ ! -f ${CONFIG_PATH}/.init_once_done ]; then
        echo "===================================================="
        echo "First run detected. Generating password..."
        echo "Generated password: ${PASSWORD}"
        echo "===================================================="
        touch ${CONFIG_PATH}/.init_once_done
    else
        echo "Password already generated. Skipping..."
    fi

    # Generate a CA certificate for Elasticsearch
    if [ ! -f ${CONFIG_PATH}/elastic-stack-ca.p12 ]; then
        echo "CA certificate does not exist. Generating..."
        elasticsearch-certutil ca \
            -o ${CONFIG_PATH}/elastic-stack-ca.p12 \
            --pass "${PASSWORD}"
    fi

    # Build cert SAN list — include seed hosts when running as a cluster
    CERT_DNS="localhost,elasticsearch"
    if [ -n "${DISCOVERY_SEED_HOSTS:-}" ]; then
        EXTRA_DNS=$(echo "${DISCOVERY_SEED_HOSTS}" | jq -r 'join(",")' 2>/dev/null)
        [ -n "$EXTRA_DNS" ] && CERT_DNS="${CERT_DNS},${EXTRA_DNS}"
    fi

    # Generate a certificate for Elasticsearch nodes
    if [ ! -f ${CONFIG_PATH}/elastic-certificates.p12 ]; then
        echo "Elasticsearch node certificate does not exist. Generating..."
        elasticsearch-certutil cert \
            -o ${CONFIG_PATH}/elastic-certificates.p12 \
            --ca ${CONFIG_PATH}/elastic-stack-ca.p12 \
            --ca-pass "${PASSWORD}" \
            --pass "${PASSWORD}" \
            --dns "${CERT_DNS}" \
            --ip 127.0.0.1
    fi

    # Set passwords for transport keystore and truststore
    cd ${ELASTIC_SHARE}
    if [ ! -f ${CONFIG_PATH}/elasticsearch.keystore ]; then
        echo "Elasticsearch keystore does not exist. Creating..."
        echo "${PASSWORD}" | elasticsearch-keystore add xpack.security.transport.ssl.keystore.secure_password
        echo "${PASSWORD}" | elasticsearch-keystore add xpack.security.transport.ssl.truststore.secure_password
        echo "${PASSWORD}" | elasticsearch-keystore add xpack.security.http.ssl.keystore.secure_password
        echo "${PASSWORD}" | elasticsearch-keystore add xpack.security.http.ssl.truststore.secure_password
        echo "${PASSWORD}" | elasticsearch-keystore add -x bootstrap.password
        cp ${ELASTIC_ETC}/elasticsearch.keystore ${CONFIG_PATH}/elasticsearch.keystore
    fi

    # Generate elasticsearch.yml in shared config
    if [ ! -f ${CONFIG_PATH}/elasticsearch.yml ]; then
        echo "Copying default elasticsearch.yml to config path..."
        cp ${ELASTIC_BUILD}/elasticsearch.yml ${CONFIG_PATH}/elasticsearch.yml

        # Use NODE_NAME env var for node name (ES resolves ${NODE_NAME} from environment at startup)
        if [ -n "${NODE_NAME:-}" ]; then
            sed -i "s/^node\.name: elasticsearch$/node.name: \${NODE_NAME}/" ${CONFIG_PATH}/elasticsearch.yml
        fi

        # Switch from single-node discovery to cluster mode when seed hosts are provided
        if [ -n "${DISCOVERY_SEED_HOSTS:-}" ]; then
            sed -i '/^discovery\.type: single-node$/d' ${CONFIG_PATH}/elasticsearch.yml
            printf '\n' >> ${CONFIG_PATH}/elasticsearch.yml
            echo "discovery.seed_hosts: ${DISCOVERY_SEED_HOSTS}" >> ${CONFIG_PATH}/elasticsearch.yml
        fi

        if [ -n "${CLUSTER_INITIAL_MASTER_NODES:-}" ]; then
            printf '\n' >> ${CONFIG_PATH}/elasticsearch.yml
            echo "cluster.initial_master_nodes: ${CLUSTER_INITIAL_MASTER_NODES}" >> ${CONFIG_PATH}/elasticsearch.yml
        fi
    fi

    # JVM heap config — half memory, capped at 30g, floored at 1g
    if [ ! -f ${CONFIG_PATH}/memory.options ]; then
        echo "Configuring JVM heap size..."
        HEAP_GB=$(free -g | awk '/Mem:/ {print int($2/2)}')
        [ "$HEAP_GB" -gt 30 ] && HEAP_GB=30
        [ "$HEAP_GB" -lt 1 ] && HEAP_GB=1
        echo "-Xms${HEAP_GB}g" > ${CONFIG_PATH}/memory.options
        echo "-Xmx${HEAP_GB}g" >> ${CONFIG_PATH}/memory.options
    fi

    touch ${CONFIG_PATH}/.init_complete
    rmdir ${CONFIG_PATH}/.init_lock 2>/dev/null
fi

# Per-node setup: distribute shared files to local paths (runs on every node)
chmod 770 ${CONFIG_PATH}/elastic-*
cp ${CONFIG_PATH}/elastic-* ${ELASTIC_SHARE}/
cp ${CONFIG_PATH}/elastic-* ${ELASTIC_ETC}/
cp ${CONFIG_PATH}/elastic-* ${SHARE_PATH}/
chown elasticsearch:elasticsearch ${ELASTIC_ETC}/elastic-*
chown elasticsearch:elasticsearch ${ELASTIC_SHARE}/elastic-*
chown elasticsearch:elasticsearch ${SHARE_PATH}/elastic-*
chown elasticsearch:elasticsearch ${ELASTIC_LOG}/

cp ${CONFIG_PATH}/elasticsearch.keystore ${ELASTIC_ETC}/elasticsearch.keystore
cp ${CONFIG_PATH}/elasticsearch.yml ${ELASTIC_ETC}/elasticsearch.yml
cp ${CONFIG_PATH}/memory.options ${ELASTIC_ETC}/jvm.options.d/memory.options


# set memory lock limits
echo "Setting memory lock limits..."
echo "elasticsearch soft memlock unlimited" >> /etc/security/limits.conf
echo "elasticsearch hard memlock unlimited" >> /etc/security/limits.conf


# add elastic lib data so it can be volumed out
if [ ! -d ${ELASTIC_LIB}/nodes ]; then
    echo "elastic lib data directory does not exist. Creating and copying default data..."
    cp -r /tmp/elasticsearch_data_lib/ ${ELASTIC_LIB}/
    chown -R elasticsearch:elasticsearch ${ELASTIC_LIB}/
else
    echo "elastic lib data directory exists. Using existing data..."
fi


echo ${PASSWORD} > /tmp/share/credential.txt

su elasticsearch -s "/usr/share/elasticsearch/bin/elasticsearch" &
ES_PID=$!

until curl --insecure --silent --output /dev/null --write-out "%{http_code}" \
    https://localhost:9200 -u "elastic:${PASSWORD}" | grep -q "200"; do
    sleep 5
    echo "Waiting for Elasticsearch API..."
done

# Monitor user creation: only the elected cluster master runs this. Followers wait
# for the master to publish .monitor_user_created via the shared config volume.
if [ ! -f ${CONFIG_PATH}/.monitor_user_created ]; then
    echo "Determining cluster master..."
    CURRENT_MASTER=""
    for i in $(seq 1 30); do
        CURRENT_MASTER=$(curl --insecure --silent -u "elastic:${PASSWORD}" \
            "https://localhost:9200/_cat/master?h=node" 2>/dev/null | tr -d ' \n\r')
        [ -n "$CURRENT_MASTER" ] && break
        sleep 2
    done

    THIS_NODE="${NODE_NAME:-elasticsearch}"
    if [ "$CURRENT_MASTER" = "$THIS_NODE" ]; then
        echo "I am master ($THIS_NODE). Creating logstash monitor user..."
        MONITOR_PASSWORD=$(< /dev/urandom tr -dc 'A-Za-z0-9' | head -c 20)

        ROLE_HTTP=$(curl --insecure --silent -o /dev/null -w "%{http_code}" \
            -u "elastic:${PASSWORD}" \
            -X PUT "https://localhost:9200/_security/role/logstash_disk_monitor" \
            -H "Content-Type: application/json" \
            -d '{"cluster":["monitor"],"indices":[],"applications":[]}')

        USER_HTTP=$(curl --insecure --silent -o /dev/null -w "%{http_code}" \
            -u "elastic:${PASSWORD}" \
            -X PUT "https://localhost:9200/_security/user/logstash_monitor" \
            -H "Content-Type: application/json" \
            -d "{\"password\":\"${MONITOR_PASSWORD}\",\"roles\":[\"logstash_disk_monitor\"],\"full_name\":\"Logstash Disk Monitor\"}")

        if [[ "$ROLE_HTTP" =~ ^2 ]] && [[ "$USER_HTTP" =~ ^2 ]]; then
            printf '%s\n' "${MONITOR_PASSWORD}" > /tmp/pub-share/logstash_monitor_cred.txt
            touch ${CONFIG_PATH}/.monitor_user_created
            echo "Logstash monitor user created."
        else
            echo "ERROR: Failed to create monitor user (role=${ROLE_HTTP} user=${USER_HTTP}). Will retry on next start."
        fi
    else
        echo "Master is '${CURRENT_MASTER}', I am '${THIS_NODE}'. Skipping monitor user creation."
    fi
else
    echo "Logstash monitor user already exists. Skipping..."
fi

wait ${ES_PID}
