#!/bin/bash
log() {
    printf "[INFO] preStart: %s\n" "$@"
}
loge() {
    printf "[ERROR] preStart: %s\n" "$@"
}

# update discovery.zen.ping.unicast.hosts
replace() {
    REPLACEMENT=$(printf 's/^discovery\.zen\.ping\.unicast\.hosts.*$/discovery\.zen\.ping\.unicast\.hosts: %s/' "${MASTER}")
    sed -i "${REPLACEMENT}" /opt/elasticsearch/config/elasticsearch.yml
}

# get the list of ES master nodes from Consul
configureMaster() {    
    #MASTER=$(curl -Ls --fail "${CONSUL}/v1/catalog/service/elasticsearch-master" | jq -e -r '.[0].ServiceAddress')
    MASTER=$(curl -Ls --fail "${CONSUL}/v1/health/service/elasticsearch-master?passing"| jq -r -e '[.[].Service.Address]' | tr -d '\r\n' | tr -d ' ')
    if [[ $MASTER != "[]" ]] && [[ -n $MASTER ]]; then
        log "MASTER: $MASTER"
        log "Master found!, joining cluster."
        replace
        log "Installing plugins"
        #plugin install -b -t 2m royrusso/elasticsearch-HQ
        exit 0
    else
        unset MASTER
        return 1
    fi
    # if there's no master we fall thru and let the caller figure
    # out what to do next
}

MASTER=[]
# happy path is that there's a master available and we can cluster
configureMaster

# data-only or client nodes can only loop until there's a master available
if [ "${ES_NODE_MASTER}" == false ]; then
    log "Client or Data only node, waiting for master"
    # Slow poll instead of spinning (2 query every 1 minutes)
    until configureMaster; do
        sleep 30
    done
fi

# for a master+data node, we'll retry for 2 minutes to see if there's 
# another master in the cluster in the process of starting up. But we
# bail out if we exceed the retries and just bootstrap the cluster
if [ "${ES_NODE_DATA}" == true ]; then
    log "Master+Data node, waiting up to 120s for master"
    n=0
    until [ $n -ge 120 ]; do
        until (curl -Ls --fail "${CONSUL}/v1/health/service/elasticsearch-master?passing" | jq -r -e '.[0].ServiceAddress' >/dev/null); do
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
MASTER=127.0.0.1
replace
