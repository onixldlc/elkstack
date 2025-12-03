#/bin/bash


until curl --insecure --silent --output /dev/null --write-out "%{http_code}" ${KIBANA_BASEURL} | grep -qE "200|401|403"; do
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

echo "Starting Logstash..."
su logstash -s /bin/bash -c "\
    /usr/share/logstash/bin/logstash -f /etc/logstash/conf.d/logstash.conf 
    --path.data /var/lib/logstash \
    --path.logs /var/log/logstash \
    --log.level info \
    --http.host"