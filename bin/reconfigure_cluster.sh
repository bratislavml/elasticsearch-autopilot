#!/bin/bash
NUM_MASTERS=$(curl -Ls --fail "${CONSUL}/v1/health/service/elasticsearch-master?passing"| jq -r -e '.[].Service.Address'|wc -l)
QUORUM=$(( (NUM_MASTERS/2)+1 ))

curl -XPUT http://elasticsearch-master:9200/_cluster/settings -d '{"persistent" : {"discovery.zen.minimum_master_nodes" : "'"${QUORUM}"'" }}'