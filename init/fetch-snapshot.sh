#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f /data/.initialized ]]; then
    mkdir -p /data/bin

    # Mainnet genesis and version
    wget -O /data/genesis.conf "${GENESIS_URL}"
    wget -O /data/bin/VERSION "${VERSION_URL}"

    # Archive/full node config (pruning disabled by default)
    wget -O /data/pharos.conf "${PHAROS_CONF_URL}"

    # # Bootstrap the node
    # rm -rf /data/bin
    # cp -r /app/bin /data/bin
    # chmod +x /data/bin/*
    # LD_PRELOAD=/data/bin/libevmone.so CONSENSUS_KEY_PWD="$CONSENSUS_KEY_PWD" PORTAL_SSL_PWD="$PORTAL_SSL_PWD" /data/bin/pharos_cli genesis -c /data/pharos.conf -g /data/genesis.conf

    # Download snapshot
    mkdir -p /data/snapshot
    cd /data/snapshot
    aria2c -c -x6 -s6 --auto-file-renaming=false --conditional-get=true --allow-overwrite=true -o snapshot.tar.gz "${SNAPSHOT}"

    # Extract 
    tar -zxvf snapshot.tar.gz
    mv /data/data/public /data/data/public_bak
    mv public/ /data/data

    touch /data/.initialized
    echo "Initialize complete"
else
    echo "No need to initialize"
fi
