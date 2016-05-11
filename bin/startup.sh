#!/bin/ash
log() {
    printf "%s\n" "$@"|awk '{print strftime("%Y/%m/%d %T",systime()),"[INFO] startup.sh:",$0}'
}
loge() {
    printf "%s\n" "$@"|awk '{print strftime("%Y/%m/%d %T",systime()),"[ERROR] startup.sh:",$0}'
}

/usr/local/bin/set-timezone.sh "$TZ"

if [[ -z ${CONSUL} ]]; then
    loge "Missing CONSUL environment variable"
    exit 1
fi

# Wait 2 minutes for Consul to be available
log "Waiting for Consul availability"
n=0
until [ $n -ge 120 ]; do
	until (curl -fsL --connect-timeout 1 "${CONSUL}/v1/status/leader" &> /dev/null); do
		sleep 2
		n=$((n+2))
	done
	log "Consul is now available [${n}s], starting up Elasticsearch"
	su-exec elasticsearch:elasticsearch /opt/containerpilot/containerpilot /opt/elasticsearch/bin/elasticsearch
done
loge "Consul unavailable, aborting"
exit 1