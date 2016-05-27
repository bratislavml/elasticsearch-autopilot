#!/bin/bash
log() {
    printf "[INFO] preStart: %s\n" "$@"
}
loge() {
    printf "[ERROR] preStart: %s\n" "$@"
}

# update config file
replace() {
    REPLACEMENT_CLUSTER=$(printf 's/^#.*cluster\.name:.*/cluster.name: %s/' "${ES_CLUSTER_NAME}")
    sed -i "${REPLACEMENT_CLUSTER}" /opt/elasticsearch/config/elasticsearch.yml

    REPLACEMENT_NAME=$(printf 's/^#.*node\.name:.*/node.name: %s/' "${HOSTNAME}")
    sed -i "${REPLACEMENT_NAME}" /opt/elasticsearch/config/elasticsearch.yml

    REPLACEMENT_NODE_MASTER=$(printf 's/^#.*node\.master:.*/node.master: %s/' "${ES_NODE_MASTER}")
    sed -i "${REPLACEMENT_NODE_MASTER}" /opt/elasticsearch/config/elasticsearch.yml

    REPLACEMENT_NODE_DATA=$(printf 's/^#.*node\.data:.*/node.data: %s/' "${ES_NODE_DATA}")
    sed -i "${REPLACEMENT_NODE_DATA}" /opt/elasticsearch/config/elasticsearch.yml

    REPLACEMENT_PATH_DATA=$(printf 's/^#.*path\.data:.*/path.data: \/elasticsearch\/data/')
    sed -i "${REPLACEMENT_PATH_DATA}" /opt/elasticsearch/config/elasticsearch.yml

    REPLACEMENT_PATH_LOGS=$(printf 's/^#.*path\.logs:.*/path.logs: \/elasticsearch\/log/')
    sed -i "${REPLACEMENT_PATH_LOGS}" /opt/elasticsearch/config/elasticsearch.yml

    if [ "$ENVIRONMENT" == "prod" ]; then {
        REPLACEMENT_BOOTSTRAP_MLOCKALL=$(printf 's/^#.*bootstrap\.mlockall:\s*true/bootstrap.mlockall: true/')
        sed -i "${REPLACEMENT_BOOTSTRAP_MLOCKALL}" /opt/elasticsearch/config/elasticsearch.yml
    }
    fi

    REPLACEMENT_NETWORK_HOST=$(printf 's/^#.*network\.host:.*/network.host: _eth0:ipv4_/')
    sed -i "${REPLACEMENT_NETWORK_HOST}" /opt/elasticsearch/config/elasticsearch.yml

    NUM_MASTERS=$(curl -Ls --fail "${CONSUL}/v1/health/service/elasticsearch-master"|jq -r -e '[.[].Service.Address] | unique | length // empty')
    NEW_QUORUM=$(( (NUM_MASTERS/2)+1 ))
    QUORUM=$(( (ES_CLUSTER_SIZE/2)+1 )) 
    if [ "$NEW_QUORUM" -gt "${QUORUM}" ]; then {
        QUORUM="$NEW_QUORUM" 
    }
    fi

    REPLACEMENT_ZEN_MIN_NODES=$(printf 's/^#.*discovery\.zen\.minimum_master_nodes:.*/discovery.zen.minimum_master_nodes: %s/' "${QUORUM}")
    sed -i "${REPLACEMENT_ZEN_MIN_NODES}" /opt/elasticsearch/config/elasticsearch.yml

    REPLACEMENT_ZEN_MCAST=$(printf "s/^#.*discovery\.zen\.ping\.multicast\.enabled:.*/discovery.zen.ping.multicast.enabled: false/")
    sed -i "${REPLACEMENT_ZEN_MCAST}" /opt/elasticsearch/config/elasticsearch.yml

    REPLACEMENT=$(printf 's/^#.*discovery\.zen\.ping\.unicast\.hosts.*/discovery.zen.ping.unicast.hosts: %s/' "${MASTER}")
    sed -i "${REPLACEMENT}" /opt/elasticsearch/config/elasticsearch.yml
}

# Get the list of ES master nodes from Consul
configureMaster() {
    MASTER=$(curl -Ls --fail "${CONSUL}/v1/health/service/elasticsearch-master"| jq -r -e -c '[.[].Service.Address]')
    if [[ $MASTER != "[]" ]] && [[ -n $MASTER ]]; then
        log "MASTER: $MASTER"
        log "Master found!, joining cluster."
        replace
        exit 0
    else
        unset MASTER
        return 1
    fi
    # if there's no master we fall thru and let the caller figure
    # out what to do next
}
#------------------------------------------------------------------------------
# Check that CONSUL environment variable exists
if [[ -z ${CONSUL} ]]; then
    loge "Missing CONSUL environment variable"
    exit 1
fi

# Wait up to 2 minutes for Consul to be available
log "Waiting for Consul availability..."
n=0
until [ $n -ge 120 ]||(curl -fsL --connect-timeout 1 "${CONSUL}/v1/status/leader" &> /dev/null); do
    sleep 2
    n=$((n+2))
done
if [ $n -ge 120 ]; then {
    loge "Consul unavailable, aborting"
    exit 1
}
fi

log "Consul is now available [${n}s], starting up Elasticsearch"
# happy path is that there's a master available and we can cluster
configureMaster

# Data-only or client nodes can only wait until there's a master available
if [ "${ES_NODE_MASTER}" == false ]; then
    log "Client or Data only node, waiting for master"
    # Slow poll instead of spinning (2 query every 1 minutes)
    until configureMaster; do
        sleep 10
    done
fi

# A master+data node will retry for 2 minutes to see if there's 
# another master in the cluster in the process of starting up. But we
# bail out if we exceed the retries and just bootstrap the cluster
if [ "${ES_NODE_DATA}" == true ]; then
    log "Master+Data node, waiting up to 120s for master"
    n=0
    until [ $n -ge 120 ]; do
        until (curl -Ls --fail "${CONSUL}/v1/health/service/elasticsearch-master?passing" | jq -r -e '.[0].Service.Address' >/dev/null); do
            sleep 5
            n=$((n+5))
        done
        configureMaster
    done
    log "Master not found. Proceed as master"
fi

# for a master-only node or master+data node that's exceeded the
# retry attempts, we'll assume this is the first master and bootstrap
# the cluster
log "MASTER node, bootstrapping..."
MASTER=["127.0.0.1"]
replace
