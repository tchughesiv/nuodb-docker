#!/bin/sh
#
#  start the NuoDB processes
#
set -x

env

# setup NUODB vars pointing to standard locations
export NUODB_HOME=/opt/nuodb
. $NUODB_HOME/etc/nuodb_setup.sh

mv /opt/nuodb/etc/default.properties.sample /opt/nuodb/etc/default.properties
sed -i "/#domainPassword =/c\domainPassword = ${DOMAIN_PASSWORD}" /opt/nuodb/etc/default.properties

mkdir -p $NUODB_LOGDIR
mkdir -p $NUODB_VARDIR

NODE_MEM="512m"


ARCHIVE_VOLUME=$NUODB_VARDIR/production-archives
ARCHIVE_LOCATION=$ARCHIVE_VOLUME/$DB_NAME

# set up BROKER vars
BROKER_OPTS="--password ${DOMAIN_PASSWORD} --broker true"
[ -n "$PEER_ADDRESS" ] && BROKER_OPTS="$BROKER_OPTS --peer ${PEER_ADDRESS}"
[ -n "$ALT_ADDRESS" ] && BROKER_OPTS="$BROKER_OPTS --advertise-alt --alt-addr ${ALT_ADDRESS}"

#confirm broker is responding
if [ "${NODE_TYPE}" != "BROKER" ]; then
    status=""
    count=1
    while [ "$status" == "" ]; do
        echo "wait 5 seconds for broker"
        sleep 5
        status="$( /opt/nuodb/bin/nuodbmgr --broker $PEER_ADDRESS --password $DOMAIN_PASSWORD --command 'show domain summary' | grep broker )"
        ((count++))
        echo "loop count: " $count
        if [ "$count" == 10 ]; then
            echo "timed out waiting for broker to respond. Exiting"
            exit 1
        fi
    done

    #clean unreachable nodes from domain state
    uuid="$(/opt/nuodb/bin/nuodbmgr --broker $PEER_ADDRESS --password $DOMAIN_PASSWORD \
        --command "show domain summary" | grep UNREACHABLE | sed 's/\(.*\)\(uuid.*\)\( .*\)/\2/g' | awk '{print $1}')"

    for id in $uuid; do
        echo $id
        #remove broker
        /opt/nuodb/bin/nuodbmgr --broker $PEER_ADDRESS --password $DOMAIN_PASSWORD --command "agent deprovision stableId $id"
        #remove host
        /opt/nuodb/bin/nuodbmgr --broker $PEER_ADDRESS --password $DOMAIN_PASSWORD \
             --command "domainstate removehostprocesses id $id database ${DB_NAME}"
    done
fi

# first start the broker
if [ "${NODE_TYPE}" == "SM" ]; then
   HOST_TAGS="-DhostTags=SM_OK=True"
elif [ "${NODE_TYPE}" == "TE" ]; then
    HOST_TAGS="-DhostTags=TE_OK=True"
fi

$JAVA_HOME/bin/java $HOST_TAGS -jar $NUODB_HOME/jar/nuoagent.jar --port ${AGENT_PORT} $BROKER_OPTS >> $NUODB_LOGDIR/agent.log 2>&1 &

# set up engine start-up vars
START_CMD="start process ${NODE_TYPE} host ${PEER_ADDRESS}:${AGENT_PORT} database ${DB_NAME}"
NODE_OPTS="--agent-port ${AGENT_PORT} --node-port ${NODE_PORT} --mem $NODE_MEM"

# add options specific to the engine type
if [ "${NODE_TYPE}" == "SM" ]; then
        START_CMD="$START_CMD archive $ARCHIVE_LOCATION"
        NODE_OPTS="$NODE_OPTS --journal enable"

        # if the archive volume is mounted, but the archive does not exist, then initialize it
        if [ -d "$ARCHIVE_VOLUME" ]; then
                [ -d "$ARCHIVE_LOCATION" ] || NODE_OPTS="$NODE_OPS --initialize"
        else
                # the archive volume is not mounted, so the archive is ephemeral
                echo "No archive volume mounted - running in DEV mode"
                mkdir -p $ARCHIVE_LOCATION
        fi
elif [ "${NODE_TYPE}" == "TE" ]; then
        NODE_OPTS="$NODE_OPTS --dba-user ${DB_USER} --dba-password ${DB_PASSWORD}"
elif [ "${NODE_TYPE}" == "BROKER" ]; then
        echo "Starting BROKER container"
else
        echo "Unimplemented node type: ${NODE_TYPE}"
        exit 1
fi

#disable thp if enabled
/bin/bash /scripts/disable_thp.sh


#start api service
/opt/nuodb/etc/nuorestsvc start

cat $NUODB_LOGDIR/agent.log
tail -f $NUODB_LOGDIR/agent.log &
