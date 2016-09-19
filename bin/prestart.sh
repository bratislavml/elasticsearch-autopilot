#!/bin/ash
log() {
	printf "[INFO] preStart: %s\n" "$@"
}
loge() {
	printf "[ERR] preStart: %s\n" "$@"
}

# Update configuration file
update_ES_configuration() {
	REPLACEMENT_CLUSTER="s/^#.*cluster\.name:.*/cluster.name: ${ES_CLUSTER_NAME}/"
	sed -i "${REPLACEMENT_CLUSTER}" /opt/elasticsearch/config/elasticsearch.yml

	REPLACEMENT_NAME="s/^#.*node\.name:.*/node.name: ${HOSTNAME}/"
	sed -i "${REPLACEMENT_NAME}" /opt/elasticsearch/config/elasticsearch.yml

	REPLACEMENT_NODE_MASTER="s/^#.*node\.master:.*/node.master: ${ES_NODE_MASTER}/"
	sed -i "${REPLACEMENT_NODE_MASTER}" /opt/elasticsearch/config/elasticsearch.yml

	REPLACEMENT_NODE_DATA="s/^#.*node\.data:.*/node.data: ${ES_NODE_DATA}/"
	sed -i "${REPLACEMENT_NODE_DATA}" /opt/elasticsearch/config/elasticsearch.yml

	REPLACEMENT_PATH_DATA='s/^#.*path\.data:.*/path.data: \/elasticsearch\/data/'
	sed -i "${REPLACEMENT_PATH_DATA}" /opt/elasticsearch/config/elasticsearch.yml

	REPLACEMENT_PATH_LOGS='s/^#.*path\.logs:.*/path.logs: \/elasticsearch\/log/'
	sed -i "${REPLACEMENT_PATH_LOGS}" /opt/elasticsearch/config/elasticsearch.yml

	if [ "$ES_ENVIRONMENT" == "prod" ]; then {
		REPLACEMENT_BOOTSTRAP_MLOCKALL='s/^#.*bootstrap\.mlockall:\s*true/bootstrap.mlockall: true/'
		sed -i "${REPLACEMENT_BOOTSTRAP_MLOCKALL}" /opt/elasticsearch/config/elasticsearch.yml
	}
	fi

	REPLACEMENT_NETWORK_HOST='s/^#.*network\.host:.*/network.host: _eth0:ipv4_/'
	sed -i "${REPLACEMENT_NETWORK_HOST}" /opt/elasticsearch/config/elasticsearch.yml

	NUM_MASTERS=$(curl -E /etc/tls/client_certificate.crt -Ls --fail "${CONSUL_HTTP_ADDR}/v1/health/service/elasticsearch-master"|jq -r -e '[.[].Service.Address] | unique | length // empty')
	NEW_QUORUM=$(( (NUM_MASTERS/2)+1 ))
	QUORUM=$(( (ES_CLUSTER_SIZE/2)+1 )) 
	if [ "$NEW_QUORUM" -gt "${QUORUM}" ]; then {
		QUORUM="$NEW_QUORUM" 
	}
	fi
	REPLACEMENT_ZEN_MIN_NODES="s/^#.*discovery\.zen\.minimum_master_nodes:.*/discovery.zen.minimum_master_nodes: ${QUORUM}/"
	sed -i "${REPLACEMENT_ZEN_MIN_NODES}" /opt/elasticsearch/config/elasticsearch.yml

	REPLACEMENT_ZEN_MCAST='s/^#.*discovery\.zen\.ping\.multicast\.enabled:.*/discovery.zen.ping.multicast.enabled: false/'
	sed -i "${REPLACEMENT_ZEN_MCAST}" /opt/elasticsearch/config/elasticsearch.yml

	REPLACEMENT="s/^#.*discovery\.zen\.ping\.unicast\.hosts.*/discovery.zen.ping.unicast.hosts: ${MASTER}/"
	sed -i "${REPLACEMENT}" /opt/elasticsearch/config/elasticsearch.yml
}

# Get the list of ES master nodes from Consul
get_ES_Master() {
	MASTER=$(curl -E /etc/tls/client_certificate.crt -Ls --fail "${CONSUL_HTTP_ADDR}/v1/health/service/elasticsearch-master"| jq -r -e -c '[.[].Service.Address]')
	if [[ $MASTER != "[]" ]] && [[ -n $MASTER ]]; then
		log "Master found ${MASTER}, joining cluster."
		update_ES_configuration
		exit 0
	else
		unset MASTER
		return 1
	fi
}
#------------------------------------------------------------------------------
# Check that CONSUL_HTTP_ADDR environment variable exists
if [[ -z ${CONSUL_HTTP_ADDR} ]]; then
	loge "Missing CONSUL_HTTP_ADDR environment variable"
	exit 1
fi

# Wait up to 2 minutes for Consul to be available
log "Waiting for Consul availability..."
n=0
until [ $n -ge 120 ]||(curl -E /etc/tls/client_certificate.crt -fsL --connect-timeout 1 "${CONSUL_HTTP_ADDR}/v1/status/leader" &> /dev/null); do
	sleep 2
	n=$((n+2))
done
if [ $n -ge 120 ]; then {
	loge "Consul unavailable, aborting"
	exit 1
}
fi

log "Consul is now available [${n}s], starting up Elasticsearch"
get_ES_Master

# Data-only or client nodes can only wait until there's a master available
if [ "${ES_NODE_MASTER}" == false ]; then
	log "Client or Data only node, waiting for master"
	until get_ES_Master; do
		sleep 10
	done
else 
	# A master+data node will retry for 2 minutes to see if there's 
	# another master in the cluster in the process of starting up. But we
	# bail out if we exceed the retries and just bootstrap the cluster
	if [ "${ES_NODE_DATA}" == true ]; then
		log "Master+Data node, waiting up to 120s for master"
		n=0
		until [ $n -ge 120 ]; do
			until (curl -E /etc/tls/client_certificate.crt -Ls --fail "${CONSUL_HTTP_ADDR}/v1/health/service/elasticsearch-master?passing" | jq -r -e '.[0].Service.Address' 
>/dev/null); do
				sleep 5
				n=$((n+5))
			done
			get_ES_Master
		done
		log "Master not found. Proceed as master"
	fi
	# for a master-only node (or master+data node that has exceeded the
	# retry attempts), we'll assume this is the first master and bootstrap
	# the cluster
	log "MASTER node, bootstrapping..."
	MASTER=["127.0.0.1"]
	update_ES_configuration
fi

