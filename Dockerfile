FROM ubuntu:xenial
MAINTAINER Jake Lee <jake@jakelee.net>
WORKDIR /tmp

ENV SQUID_CACHE_DIR=/var/cache/squid
ENV SQUID_LOG_DIR=/var/log/squid
ENV SQUID_USER=proxy
ENV SQUID_VERSION=4.0.12
ENV SQUID_ARCHIVE=squid-${SQUID_VERSION}
ENV SQUID_DOWNLOAD_URL=http://www.squid-cache.org/Versions/v4/${SQUID_ARCHIVE}.tar.gz

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential clang && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ADD ${SQUID_DOWNLOAD_URL} /tmp
ADD ${SQUID_DOWNLOAD_URL}.asc /tmp
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys FF5CF463 && \
    apt-key adv --verify ${SQUID_ARCHIVE}.tar.gz.asc ${SQUID_ARCHIVE}.tar.gz && \
    tar -xzf ${SQUID_ARCHIVE}.tar.gz && \
    rm ${SQUID_ARCHIVE}.tar.gz

RUN cd $SQUID_ARCHIVE && \
    CC=clang CFLAGS=-O3 CXX=clang++ CXXFLAGS=-O3 ./configure \
        --prefix=/usr \
        --localstatedir=/var \
        --libexecdir=/usr/lib/squid \
        --datadir=/usr/share/squid \
        --sysconfdir=/etc/squid \
        --with-default-user=$SQUID_USER \
        --with-logdir=$SQUID_LOG_DIR \
        --with-pidfile=/var/run/squid.pid && \
    make -j $(cat /proc/cpuinfo | grep processor | wc -l) && \
    make install && \
    cd .. && \
    rm -rf ${SQUID_ARCHIVE}*

ADD squid.conf.sh .
ADD http://mirrors.ubuntu.com/mirrors.txt .
RUN bash squid.conf.sh > /etc/squid/squid.conf && \
    apt-get remove -y build-essential clang && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf squid.conf.sh /var/lib/apt/lists/*

ADD entrypoint.sh /sbin/entrypoint.sh
RUN chmod 755 /sbin/entrypoint.sh

EXPOSE 3128
VOLUME ["$SQUID_CACHE_DIR", "$SQUID_LOG_DIR"]
ENTRYPOINT ["/sbin/entrypoint.sh"]
