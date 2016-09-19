#!/bin/ash
#if curl --fail -s -o /dev/null "http://$(hostname -i):9200"; then
#	exit 0
#elif [ $? -eq 22 ]; then # Exit status on ES startup, investigate.
#	exit 0
#else
#	exit 1
#fi
curl --fail -Ls ${HOSTNAME}:9200/_cluster/state/nodes
