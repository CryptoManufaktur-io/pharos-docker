ARG DOCKER_TAG=pharos_community_v0.12.2_f301031a_0422
ARG DOCKER_REPO=public.ecr.aws/k2g7b7g1/pharos

FROM ${DOCKER_REPO}:${DOCKER_TAG}

COPY fetch-snapshot.sh /usr/local/bin/
RUN chmod -R 755 /usr/local/bin/*

RUN apt-get update && DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC apt-get install -y ca-certificates tzdata aria2 curl zstd lz4 \
        && rm -rf /var/lib/apt/lists/*

ENTRYPOINT [ "fetch-snapshot.sh" ]
