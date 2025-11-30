#/bin/bash

if [ -f ${SHARE_PATH}/credential.txt ]; then
    RANDOM_PASSWORD=$(cat ${SHARE_PATH}/credential.txt)
else
    RANDOM_PASSWORD=$(< /dev/urandom tr -dc 'A-Za-z0-9' | head -c 8)
fi

PASSWORD=${ELASTIC_PASSWORD:-$RANDOM_PASSWORD}
CONFIG_PATH="/tmp/config"
SHARE_PATH="/tmp/share"
ELASTIC_SHARE="/usr/share/elasticsearch"
ELASTIC_ETC="/etc/elasticsearch"
ELASTIC_BUILD="/elastic"
ELASTIC_LOG="/var/log/elasticsearch"
ELASTIC_LIB="/var/lib/elasticsearch"
mkdir -p ${CONFIG_PATH}
mkdir -p ${SHARE_PATH}

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

# Generate a certificate for Elasticsearch nodes
if [ ! -f ${CONFIG_PATH}/elastic-certificates.p12 ]; then
    echo "Elasticsearch node certificate does not exist. Generating..."
    elasticsearch-certutil cert \
        -o ${CONFIG_PATH}/elastic-certificates.p12 \
        --ca ${CONFIG_PATH}/elastic-stack-ca.p12 \
        --ca-pass "${PASSWORD}" \
        --pass "${PASSWORD}" \
        --dns localhost,elasticsearch \
        --ip 127.0.0.1
fi
chmod 770 ${CONFIG_PATH}/elastic-*
cp ${CONFIG_PATH}/elastic-* ${ELASTIC_SHARE}/
cp ${CONFIG_PATH}/elastic-* ${ELASTIC_ETC}/
cp ${CONFIG_PATH}/elastic-* ${SHARE_PATH}/
chown elasticsearch:elasticsearch ${ELASTIC_ETC}/elastic-*
chown elasticsearch:elasticsearch ${ELASTIC_SHARE}/elastic-*
chown elasticsearch:elasticsearch ${SHARE_PATH}/elastic-*
chown elasticsearch:elasticsearch ${ELASTIC_LOG}/

# set passwords for transport keystore and truststore
cd ${ELASTIC_SHARE}
if [ ! -f ${CONFIG_PATH}/elasticsearch.keystore ]; then
    echo "Elasticsearch keystore does not exist. Creating..."
    echo "${PASSWORD}" | elasticsearch-keystore add xpack.security.transport.ssl.keystore.secure_password
    echo "${PASSWORD}" | elasticsearch-keystore add xpack.security.transport.ssl.truststore.secure_password
    echo "${PASSWORD}" | elasticsearch-keystore add xpack.security.http.ssl.keystore.secure_password
    echo "${PASSWORD}" | elasticsearch-keystore add xpack.security.http.ssl.truststore.secure_password
    echo "${PASSWORD}" | elasticsearch-keystore add -x bootstrap.password
    cp ${ELASTIC_ETC}/elasticsearch.keystore ${CONFIG_PATH}/elasticsearch.keystore
else
    echo "Elasticsearch keystore exists. Restoring..."
    cp ${CONFIG_PATH}/elasticsearch.keystore ${ELASTIC_ETC}/elasticsearch.keystore
fi


# move elasticsearch.yml to config path if its not there
if [ ! -f ${CONFIG_PATH}/elasticsearch.yml ]; then
    echo "Copying default elasticsearch.yml to config path..."
    cp ${ELASTIC_BUILD}/elasticsearch.yml ${CONFIG_PATH}/elasticsearch.yml
    cp ${ELASTIC_BUILD}/elasticsearch.yml ${ELASTIC_ETC}/elasticsearch.yml
else
    echo "elasticsearch.yml already exists in config path. using existing file..."
    cp ${CONFIG_PATH}/elasticsearch.yml ${ELASTIC_ETC}/elasticsearch.yml
fi


# set memory lock limits
echo "Setting memory lock limits..."
echo "elasticsearch soft memlock unlimited" >> /etc/security/limits.conf
echo "elasticsearch hard memlock unlimited" >> /etc/security/limits.conf


# configure JVM heap size to half of system memory
echo "Configuring JVM heap size..."
HALF_MEMORY=$(free -g | grep Mem | awk '{print int(($2/2)%30)}')
if [ ! -f ${CONFIG_PATH}/memory.options ]; then
    touch ${CONFIG_PATH}/memory.options
    echo "-Xms${HALF_MEMORY}g" >> ${CONFIG_PATH}/memory.options
    echo "-Xmx${HALF_MEMORY}g" >> ${CONFIG_PATH}/memory.options
fi
cp ${CONFIG_PATH}/memory.options ${ELASTIC_ETC}/jvm.options.d/memory.options


# add elastic lib data so it can be volumed out
if [ ! -d ${ELASTIC_LIB} ]; then
    echo "elastic lib data directory does not exist. Creating and copying default data..."
    cp -r /tmp/elasticsearch_data_lib/ ${ELASTIC_LIB}/
    chown -R elasticsearch:elasticsearch ${ELASTIC_LIB}/
else
    echo "elastic lib data directory exists. Using existing data..."
fi


echo ${PASSWORD} > /tmp/share/credential.txt
su elasticsearch -s "/usr/share/elasticsearch/bin/elasticsearch"