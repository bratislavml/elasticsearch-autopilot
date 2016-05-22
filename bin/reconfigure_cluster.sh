#!/bin/bash
log() {
    printf "[INFO] reconfigure-cluster: %s\n" "$@"
}

NUM_MASTERS=$(curl -Ls --fail "${CONSUL}/v1/health/service/elasticsearch-master"|jq -r -e '[.[].Service.Address] | unique | length')
NEW_QUORUM=$(( (NUM_MASTERS/2)+1 ))
OLD_QUORUM=$(curl -s http://elasticsearch-master:9200/_cluster/settings|jq -r -e '.persistent.discovery.zen.minimum_master_nodes // empty')
OLD_QUORUM=${OLD_QUORUM:=$(( (ES_CLUSTER_SIZE/2)+1 ))}
if [ "$NEW_QUORUM" -gt "${OLD_QUORUM}" ]; then
	log "Scaling Elasticsearch cluster ${ES_CLUSTER_NAME}. Setting quorum to ${NEW_QUORUM} from ${OLD_QUORUM}"
	curl -s -XPUT http://elasticsearch-master:9200/_cluster/settings -d '{"persistent" : {"discovery.zen.minimum_master_nodes" : "'"${NEW_QUORUM}"'" }}'
fi