FROM ubuntu:xenial
MAINTAINER Jake Lee <jake@jakelee.net>

ENV SQUID_CACHE_DIR=/var/spool/squid \
    SQUID_LOG_DIR=/var/log/squid \
    SQUID_USER=proxy

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y squid wget && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ADD squid.conf.sh .
RUN bash squid.conf.sh > /etc/squid/squid.conf && \
    rm squid.conf.sh && \
    apt-get remove -y wget && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ADD entrypoint.sh /sbin/entrypoint.sh
RUN chmod 755 /sbin/entrypoint.sh

EXPOSE 3128
VOLUME ["$SQUID_CACHE_DIR"]
ENTRYPOINT ["/sbin/entrypoint.sh"]
