FROM alpine:3.3

# Alpine packages
RUN echo http://dl-6.alpinelinux.org/alpine/v3.3/community >> /etc/apk/repositories &&\
	apk upgrade --update &&\
	apk -f -q --no-progress --no-cache add \
		curl \
		bash \
		ca-certificates \
		jq \
		libcap \
		openjdk8-jre-base \
		openssl \
		su-exec \
		tzdata

WORKDIR /tmp
# Add Containerpilot and set its configuration path
ENV CONTAINERPILOT_VERSION=2.1.2 \
	CONTAINERPILOT=file:///etc/containerpilot/containerpilot.json
ADD https://github.com/joyent/containerpilot/releases/download/${CONTAINERPILOT_VERSION}/containerpilot-${CONTAINERPILOT_VERSION}.tar.gz /tmp/
ADD	https://github.com/joyent/containerpilot/releases/download/${CONTAINERPILOT_VERSION}/containerpilot-${CONTAINERPILOT_VERSION}.sha1.txt /tmp/
RUN	sha1sum -sc containerpilot-${CONTAINERPILOT_VERSION}.sha1.txt &&\
	mkdir -p /opt/containerpilot &&\
	tar xzf containerpilot-${CONTAINERPILOT_VERSION}.tar.gz -C /opt/containerpilot/ &&\
	rm -f containerpilot-${CONTAINERPILOT_VERSION}.*

# get Elasticsearch release
ENV ES_VERSION=2.3.2
ADD https://download.elastic.co/elasticsearch/release/org/elasticsearch/distribution/tar/elasticsearch/${ES_VERSION}/elasticsearch-${ES_VERSION}.tar.gz /tmp/
RUN mkdir -p /opt &&\
	tar xzf elasticsearch-${ES_VERSION}.tar.gz &&\
	mv elasticsearch-${ES_VERSION} /opt/elasticsearch &&\
	rm -f elasticsearch-${ES_VERSION}.tar.gz

EXPOSE 9200 9300
ENV PATH=$PATH:/opt/elasticsearch/bin

# Copy internal CA certificate bundle.
COPY ca.pem /etc/ssl/private/
# Create and take ownership over required directories, update CA
RUN adduser -D -H -g elasticsearch elasticsearch &&\
	adduser elasticsearch elasticsearch &&\
	mkdir /elasticsearch/ &&\
	chmod -R g+w /elasticsearch &&\
	mkdir -p /etc/containerpilot &&\
	chmod -R g+w /etc/containerpilot &&\
	plugin install license &&\
	plugin install marvel-agent &&\
	chown -R elasticsearch:elasticsearch /elasticsearch &&\
	chown -R elasticsearch:elasticsearch /opt &&\
	chown -R elasticsearch:elasticsearch /etc/containerpilot &&\
	$(cat /etc/ssl/private/ca.pem >> /etc/ssl/certs/ca-certificates.crt;exit 0)

# Add our configuration files and scripts
COPY bin/* /usr/local/bin/
COPY containerpilot.json /etc/containerpilot/containerpilot.json
COPY logging.yml /opt/elasticsearch/config/logging.yml

# If you build on top of this image, please provide this files
# If you are using an internal CA
ONBUILD COPY ca.pem /etc/ssl/private/
ONBUILD COPY containerpilot.json /etc/containerpilot/containerpilot.json
ONBUILD COPY logging.yml /opt/elasticsearch/config/logging.yml

# Put Elasticsearch data on a separate volume to avoid filesystem performance issues with Docker image layers
VOLUME ["/elasticsearch"]

USER elasticsearch
CMD ["/usr/local/bin/startup.sh"]
