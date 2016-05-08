#!/bin/ash
log() {
    printf "%s\n" "$@"|awk '{print strftime("%Y/%m/%d %T",systime()),"[INFO] startup.sh:",$0}'
}
loge() {
    printf "%s\n" "$@"|awk '{print strftime("%Y/%m/%d %T",systime()),"[ERROR] startup.sh:",$0}'
}

if [[ -z ${CONSUL} ]]; then
    loge "Missing CONSUL environment variable"
    exit 1
fi

log "Waiting for consul availability"
n=0
until [ $n -ge 120 ]; do
	until (curl -fsL --connect-timeout 1 https://"$CONSUL":8501/v1/status/leader &> /dev/null); do
	    sleep 2
	    n=$((n+2))
	done
	log "Consul is now available [${n}s], starting up Elasticsearch"
	exec /opt/containerpilot/containerpilot /opt/elasticsearch/bin/elasticsearch
done
loge "Consul unavailable, aborting"