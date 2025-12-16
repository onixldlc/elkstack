#/bin/bash

# wait until all elastic is running
echo "Waiting for Elasticsearch to be available..."
for ELASTIC_URL in $(echo ${ELASTICSEARCH_URLS} | jq -r '.[]'); do
    echo "Checking ${ELASTIC_URL}..."
    until curl --insecure --silent --output /dev/null --write-out "%{http_code}" ${ELASTIC_URL} | grep -qE "200|401|403"; do
        sleep 5
        echo "Still waiting for ${ELASTIC_URL}..."
    done
    echo "Elasticsearch at ${ELASTIC_URL} is running!"
done
echo "All Elasticsearch nodes are available!"


PASSWORD=$(cat /tmp/share/credential.txt)
CONFIG_PATH="/tmp/config"
SHARE_PATH="/tmp/share"
KIBANA_LIB="/usr/share/kibana"
KIBANA_ETC="/etc/kibana"
KIBANA_BUILD="/kibana"
KIBANA_LOG="/var/log/kibana"
mkdir -p ${CONFIG_PATH}
mkdir -p ${SHARE_PATH}

cd ${CONFIG_PATH}

if [ ! -f ${CONFIG_PATH}/elasticsearchca.pem ]; then
    openssl pkcs12 -in ${SHARE_PATH}/elastic-certificates.p12 -cacerts -nokeys \
    -out ${CONFIG_PATH}/elasticsearchca.pem -passin pass:${PASSWORD}
fi
if [ ! -f ${CONFIG_PATH}/server-kibana.crt ]; then
    openssl pkcs12 -in ${SHARE_PATH}/elastic-certificates.p12 -clcerts -nokeys \
    -out ${CONFIG_PATH}/server-kibana.crt -passin pass:${PASSWORD}
fi
if [ ! -f ${CONFIG_PATH}/server-kibana.key ]; then
    openssl pkcs12 -in ${SHARE_PATH}/elastic-certificates.p12 -nocerts -nodes \
    -out ${CONFIG_PATH}/server-kibana.key -passin pass:${PASSWORD}
fi


chmod 770 ${CONFIG_PATH}/elasticsearchca.pem
chmod 770 ${CONFIG_PATH}/server-kibana.*
cp ${CONFIG_PATH}/elasticsearchca.pem ${KIBANA_ETC}/
cp ${CONFIG_PATH}/server-kibana.* ${KIBANA_ETC}/
cp ${CONFIG_PATH}/elasticsearchca.pem ${SHARE_PATH}/
cp ${CONFIG_PATH}/server-kibana.* ${SHARE_PATH}/
chown kibana:kibana ${KIBANA_LOG}/
chown kibana:kibana ${KIBANA_ETC}/elasticsearchca.pem
chown kibana:kibana ${KIBANA_ETC}/server-kibana.*

if [ ! -f ${CONFIG_PATH}/kibana.keystore ]; then
    echo "Kibana keystore does not exist. Creating..."
    kibana-keystore create
    echo "${PASSWORD}" | kibana-keystore add elasticsearch.password -x
    cp ${KIBANA_ETC}/kibana.keystore ${CONFIG_PATH}/kibana.keystore
    cp ${CONFIG_PATH}/kibana.keystore ${KIBANA_LIB}/kibana.keystore
else
    echo "Kibana keystore already exists. using existing file..."
    cp ${CONFIG_PATH}/kibana.keystore ${KIBANA_LIB}/kibana.keystore
fi


if [ ! -f ${CONFIG_PATH}/kibana.yml ]; then
    echo "Using default kibana.yml to config path..."
    cp ${KIBANA_BUILD}/kibana.yml ${CONFIG_PATH}/kibana.yml
    cp ${CONFIG_PATH}/kibana.yml ${KIBANA_ETC}/kibana.yml
else
    cp ${CONFIG_PATH}/kibana.yml ${KIBANA_ETC}/kibana.yml
    echo "kibana.yml already exists in config path. using existing file..."
fi

# setup kibana.yml to use environment variables
HAS_TEMPLATE_HOST=$(cat ${CONFIG_PATH}/kibana.yml | grep TEMPLATE_HOST | wc -l)
if [ ${HAS_TEMPLATE_HOST} -gt 0 ]; then
    echo "Host template detected. Replacing with environment variable..."
    sed -i "s|TEMPLATE_HOST|${KIBANA_HOST}|g" ${KIBANA_ETC}/kibana.yml
fi
HAS_TEMPLATE_PORT=$(cat ${CONFIG_PATH}/kibana.yml | grep TEMPLATE_PORT | wc -l)
if [ ${HAS_TEMPLATE_PORT} -gt 0 ]; then
    echo "Port template detected. Replacing with environment variable..."
    sed -i "s|TEMPLATE_PORT|${KIBANA_PORT}|g" ${KIBANA_ETC}/kibana.yml
fi
HAS_TEMPLATE_BASEURL=$(cat ${CONFIG_PATH}/kibana.yml | grep TEMPLATE_BASEURL | wc -l)
if [ ${HAS_TEMPLATE_BASEURL} -gt 0 ]; then
    echo "BaseUrl template detected. Replacing with environment variable..."
    sed -i "s|TEMPLATE_BASEURL|${KIBANA_BASEURL}|g" ${KIBANA_ETC}/kibana.yml
fi
HAS_TEMPLATE_URL=$(cat ${CONFIG_PATH}/kibana.yml | grep TEMPLATE_ELASTICSEARCH_URLS | wc -l)
if [ ${HAS_TEMPLATE_URL} -gt 0 ]; then
    echo "Url template detected. Replacing with environment variable..."
    sed -i "s|TEMPLATE_ELASTICSEARCH_URLS|${ELASTICSEARCH_URLS}|g" ${KIBANA_ETC}/kibana.yml
fi
HAS_TEMPLATE_PASSWORD=$(cat ${CONFIG_PATH}/kibana.yml | grep TEMPLATE_PASSWORD | wc -l)
if [ ${HAS_TEMPLATE_PASSWORD} -gt 0 ]; then
    echo "Password template detected. Replacing with generated password..."
    sed -i "s|TEMPLATE_PASSWORD|${PASSWORD}|g" ${KIBANA_ETC}/kibana.yml
fi


# setup kibana encryption key
HAS_XPACKS=$(cat ${CONFIG_PATH}/kibana.yml | grep "xpack.encryptedSavedObjects.encryptionKey:" | wc -l)
if [ ${HAS_XPACKS} -eq 0 ]; then
    echo "Adding kibana encryption key to kibana.yml..."
    XPACKS=$(kibana-encryption-keys generate | grep xpack. | tail -3)
    echo -e "\n" >> ${KIBANA_ETC}/kibana.yml
    echo "${XPACKS}" >> ${KIBANA_ETC}/kibana.yml

    echo -e "\n" >> ${CONFIG_PATH}/kibana.yml
    echo "${XPACKS}" >> ${CONFIG_PATH}/kibana.yml
fi


# start up kibana
[ ! -d "/var/run/kibana/" ] && mkdir "/var/run/kibana/"
chown -R kibana:kibana /var/run/kibana/
chmod 755 "/var/run/kibana/"

# Set environment variables from init.d script
export KBN_PATH_CONF="/etc/kibana"
export NODE_OPTIONS="--max-old-space-size=4096"

# Ensure log directory exists
mkdir -p ${KIBANA_LOG}
chown -R kibana:kibana ${KIBANA_LOG}


su kibana -s /bin/bash -c "/usr/share/kibana/bin/kibana \
    --logging.dest=/var/log/kibana/kibana.log \
    --deprecation.skip_deprecated_settings[0]=logging.dest
    " 2>&1 | tee -a ${KIBANA_LOG}/startup.log

bash