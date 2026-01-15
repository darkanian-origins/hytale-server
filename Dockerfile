# syntax=docker/dockerfile:1.7

# ------------------------------------------------------
#               STAGE 1: Builder
# ------------------------------------------------------
FROM eclipse-temurin:25-jre AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl 7zip dos2unix && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN curl -L -o hytale.zip https://downloader.hytale.com/hytale-downloader.zip && \
    7z x hytale.zip -y -o./hytale -mmt=on && \
    mv ./hytale/hytale-downloader-linux-amd64 ./hytale-downloader && \
    chmod +x ./hytale-downloader && \
    rm hytale.zip

COPY scripts/ ./scripts/
COPY entrypoint.sh .
RUN find scripts -type f -name "*.sh" -exec dos2unix {} + && \
    dos2unix entrypoint.sh && \
    chmod -R +x scripts && \
    chmod +x entrypoint.sh

# ------------------------------------------------------
#                STAGE 2: Runtime
# ------------------------------------------------------
FROM eclipse-temurin:25-jre

ENV USER=container \
    HOME=/home/container \
    UID=1000 \
    GID=1000 \
    SCRIPTS_PATH="/usr/local/bin/scripts" \
    SERVER_PORT=5520 \
    PROD=FALSE \
    DEBUG=FALSE

RUN apt-get update && apt-get install -y --no-install-recommends \
    tini iproute2 ca-certificates tzdata jq 7zip curl && \
    rm -rf /var/lib/apt/lists/*

COPY --from=tianon/gosu:1.19 /gosu /usr/local/bin/

RUN if getent passwd ${UID} > /dev/null 2>&1; then \
        EXISTING_USER=$(getent passwd ${UID} | cut -d: -f1); \
        usermod -l ${USER} -d ${HOME} -m ${EXISTING_USER}; \
    else \
        groupadd -g ${GID} ${USER} && \
        useradd -m -d ${HOME} -u ${UID} -g ${USER} -s /bin/sh ${USER}; \
    fi

COPY --from=builder --chown=root:root /build/hytale-downloader /usr/local/bin/hytale-downloader
COPY --from=builder --chown=${UID}:${GID} /build/scripts/ /usr/local/bin/scripts/
COPY --from=builder --chown=${UID}:${GID} /build/entrypoint.sh /entrypoint.sh

ARG BUILDTIME=local
ARG VERSION=local
ARG REVISION=local
RUN printf "buildtime=${BUILDTIME}\nversion=${VERSION}\nrevision=${REVISION}\n" > /etc/image.properties

WORKDIR ${HOME}
USER root
EXPOSE ${SERVER_PORT}/udp
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=30s --timeout=5s --start-period=2m --retries=3 \
    CMD ss -ulpn | grep -q ":${SERVER_PORT}" || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/bin/sh", "/entrypoint.sh"]