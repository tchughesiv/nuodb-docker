#!/bin/bash

#handle environment types
if [ "${ENV_TYPE}" == "OPENSHIFT" ]; then
    /bin/bash /scripts/openshift.sh

elif [ "${ENV_TYPE}" == "AWSECS" ]; then
    IPADDRESS="$(ifconfig eth0 | grep broadcast | awk '{print $2}')"
    export ALT_ADDRESS=$IPADDRESS

elif [ "${ENV_TYPE}" == "AWSEC2" ]; then
    echo "placeholder for AWSEC2"
elif [ "${ENV_TYPE}" == "AZURE" ]; then
    echo "placehodler for AZURE"
elif [ "${ENV_TYPE}" == "GOOGLE" ]; then
    echo "placeholder for GOOGLE"
fi

#run startNuodb.sh for starting nuodb broker, sm, and te containers
/bin/bash /scripts/startNuodb.sh


#trap SIGTERM event and remove host
trap '/opt/nuodb/bin/nuodbmgr --broker ${PEER_ADDRESS} --password ${DOMAIN_PASSWORD} --command \"remove host address $IPADDRESS database ${DB_NAME}\"' SIGTERM

while true; do sleep 3; done



