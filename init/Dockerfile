FROM alpine:3.20

RUN apk add --no-cache aria2 bash ca-certificates coreutils curl gzip tar

COPY restore-snapshot.sh /usr/local/bin/restore-snapshot.sh

ENTRYPOINT [ "restore-snapshot.sh" ]
