FROM alpine:3.3

# Alpine packages
RUN echo http://dl-6.alpinelinux.org/alpine/v3.3/community >> /etc/apk/repositories &&\
	apk upgrade --update &&\
	apk -f -q --no-progress --no-cache add \
		curl \
		bash \
		ca-certificates \
		jq \
		openjdk8-jre-base \
		openssl \
		su-exec \
		tzdata

# We don't need to expose these ports in order for other containers on Triton
# to reach this container in the default networking environment, but if we
# leave this here then we get the ports as well-known environment variables
# for purposes of linking.
EXPOSE 9200 9300

# Add Containerpilot and set its configuration path
ENV CONTAINERPILOT_VERSION=2.1.1 \
	CONTAINERPILOT=file:///etc/containerpilot/containerpilot.json
RUN curl -# -LO https://github.com/joyent/containerpilot/releases/download/${CONTAINERPILOT_VERSION}/containerpilot-${CONTAINERPILOT_VERSION}.tar.gz &&\
	curl -# -LO https://github.com/joyent/containerpilot/releases/download/${CONTAINERPILOT_VERSION}/containerpilot-${CONTAINERPILOT_VERSION}.sha1.txt &&\
	sha1sum -sc containerpilot-${CONTAINERPILOT_VERSION}.sha1.txt &&\
	mkdir -p /opt/containerpilot &&\
	tar xzf containerpilot-${CONTAINERPILOT_VERSION}.tar.gz -C /opt/containerpilot/ &&\
	rm -f containerpilot-${CONTAINERPILOT_VERSION}.*

# get Elasticsearch release
ENV ES_VERSION=2.3.2
RUN mkdir -p /opt &&\
	curl -# -Lo /tmp/elasticsearch.tar.gz https://download.elastic.co/elasticsearch/release/org/elasticsearch/distribution/tar/elasticsearch/${ES_VERSION}/elasticsearch-${ES_VERSION}.tar.gz &&\
	tar xzf /tmp/elasticsearch.tar.gz &&\
	mv elasticsearch-${ES_VERSION} /opt/elasticsearch &&\
	rm -f /tmp/elasticsearch.tar.gz

# Copy internal CA certificate bundle.
COPY ca.pem /etc/ssl/private/
# Create and take ownership over required directories, update CA
RUN adduser -D -H -g elasticsearch elasticsearch &&\
	adduser elasticsearch elasticsearch &&\
	mkdir -p /elasticsearch/data &&\
	mkdir /elasticsearch/log &&\
	chmod -R g+w /elasticsearch &&\
	chown -R elasticsearch:elasticsearch /elasticsearch &&\
	chown -R elasticsearch:elasticsearch /opt &&\
	mkdir -p /etc/containerpilot &&\
	chmod -R g+w /etc/containerpilot &&\
	chown -R elasticsearch:elasticsearch /etc/containerpilot &&\
	$(cat /etc/ssl/private/ca.pem >> /etc/ssl/certs/ca-certificates.crt;exit 0)

#USER elasticsearch
ENV PATH=$PATH:/opt/elasticsearch/bin

# Add our configuration files and scripts
COPY bin/* /usr/local/bin/
COPY containerpilot.json /etc/containerpilot/containerpilot.json
COPY logging.yml /opt/elasticsearch/config/logging.yml
COPY elasticsearch.yml /opt/elasticsearch/config/elasticsearch.yml

# If you build on top of this image, please provide this files
ONBUILD COPY ca.pem /etc/ssl/private/
ONBUILD COPY containerpilot.json /etc/containerpilot/containerpilot.json
ONBUILD COPY logging.yml /opt/elasticsearch/config/logging.yml
ONBUILD COPY elasticsearch.yml /opt/elasticsearch/config/elasticsearch.yml

# Put Elasticsearch data on a separate volume to avoid filesystem performance issues with Docker image layers
VOLUME ["/elasticsearch"]

CMD ["/usr/local/bin/startup.sh"]
