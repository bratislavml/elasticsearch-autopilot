#!/bin/ash
log() {
	printf "[INFO] reconfigure-cluster: %s\n" "$@"
}
logd() {
	printf "[DEBUG] reconfigure-cluster: %s\n" "$@"
}
##########################################################################################################
# Prevent multiple events by waiting up to 10 seconds to quiesce changes
if [ "$ES_NODE_MASTER" == 'false' ]; then
	exit 0
fi

sleep $(( (RANDOM % 5) + 5 ))s

# If we are not a dedicated master node, wait an extra 15s to give the master a chance to write the change
if [ "$ES_NODE_DATA" == 'true' ]; then
	sleep $(( (RANDOM % 5) + 10 ))s
fi

NUM_MASTERS=$(curl -E /etc/tls/client_certificate.crt -Ls --fail "${CONSUL_HTTP_ADDR}/v1/health/service/elasticsearch-master"|jq -r -e '[.[].Service.Address] | unique | length')
NEW_QUORUM=$(( (NUM_MASTERS/2)+1 ))

OLD_QUORUM=$(curl -s http://elasticsearch-master:9200/_cluster/settings|jq -r -e '.persistent.discovery.zen.minimum_master_nodes // empty')

# Handle initial status where the cluster setting is undefined
if [ -z "$OLD_QUORUM" ] && [ "$ES_NODE_MASTER" == 'true' ]; then
	OLD_QUORUM=${OLD_QUORUM:=$(( (ES_CLUSTER_SIZE/2)+1 ))}
	log "Setting initial Elasticsearch cluster size"
	curl -s -XPUT http://elasticsearch-master:9200/_cluster/settings -d '{"persistent" : {"discovery.zen.minimum_master_nodes" : "'"${OLD_QUORUM}"'" }}'
	exit 0
fi

if [ "$NEW_QUORUM" -ne "${OLD_QUORUM}" ]; then
	if [ "$NEW_QUORUM" -gt "${OLD_QUORUM}" ]; then
		log "Scaling up Elasticsearch cluster ${ES_CLUSTER_NAME}. Setting quorum to ${NEW_QUORUM} from ${OLD_QUORUM}"
		curl -s -XPUT http://elasticsearch-master.service.consul:9200/_cluster/settings -d '{"persistent" : {"discovery.zen.minimum_master_nodes" : "'"${NEW_QUORUM}"'" }}'
	else
		log "Automatic scaling down is not supported to prevent split brain scenarios, please set the new quorum manually by: PUT '{\"persistent\" : {\"discovery.zen.minimum_master_nodes\" : \"${NEW_QUORUM}\" }}'"
	fi
fi
