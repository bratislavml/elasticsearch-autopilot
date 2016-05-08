#!/bin/bash
log() {
    printf "[INFO] preStart: %s\n" "$@"
}
loge() {
    printf "[ERROR] preStart: %s\n" "$@"
}

# update discovery.zen.ping.unicast.hosts
replace() {
    REPLACEMENT=$(printf 's/^discovery\.zen\.ping\.unicast\.hosts.*$/discovery.zen.ping.unicast.hosts: ["%s"]/' "${MASTER}")
    sed -i "${REPLACEMENT}" /opt/elasticsearch/config/elasticsearch.yml
}

# get the list of ES master nodes from Consul
configureMaster() {
    MASTER=$(curl -Ls --fail "https://${CONSUL}:8501/v1/catalog/service/elasticsearch-master" | jq -r '.[0].ServiceAddress')
    if [[ $MASTER != "null" ]] && [[ -n $MASTER ]]; then
        log "Master found!, joining cluster."
        replace
        exit 0
    else
        return 1
    fi
    # if there's no master we fall thru and let the caller figure
    # out what to do next
}

MASTER=null

# happy path is that there's a master available and we can cluster
configureMaster

# data-only or client nodes can only loop until there's a master available
if [ "${ES_NODE_MASTER}" == false ]; then
    log "Client or Data only node, waiting for master"
    until configureMaster; do
        sleep 5
    done
    exit 0
fi

# for a master+data node, we'll retry for 2 minutes to see if there's 
# another master in the cluster in the process of starting up. But we
# bail out if we exceed the retries and just bootstrap the cluster
if [ "${ES_NODE_DATA}" == true ]; then
    log "Master+Data node, waiting 120s for master"
    n=0
    until [ $n -ge 120 ]
    do
        sleep 2
        configureMaster
        n=$((n+2))
    done
    log "Master not found. Proceed as master"
fi

# for a master-only node or master+data node that's exceeded the
# retry attempts, we'll assume this is the first master and bootstrap
# the cluster
log "MASTER node, bootstrapping..."
MASTER=127.0.0.1
replace