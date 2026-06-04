#!/usr/bin/env bash
set -euo pipefail

# Headless Pharos snapshot restore.
#
# The Pharos snapshot archive contains only the `public` chain database. The node
# must first bootstrap its keys + base chain data (meta_store, public, ...), and
# only then can the snapshot's `public` replace the freshly-bootstrapped one. If
# the snapshot is dropped into a bare volume, the node's entrypoint sees no
# meta_store, runs genesis, and clobbers/ignores the snapshot - so it must be
# bootstrapped first.
#
# This runs inside the one-shot init container, which is built FROM the node
# image, so the node binaries (/app/bin, /app/ops) and config are available. We
# bootstrap with `pharos_cli genesis`, which creates meta_store + a base public
# and exits cleanly on its own (no long-running node process to stop/kill).
#
# Markers, in order:
#   /data/.bootstrapped - genesis ran and generated keys + base chain data
#   /data/.initialized  - snapshot `public` swapped in; restore is complete
#
# Safety: the node's own "already bootstrapped" sentinel is /data/data/meta_store.
# If that exists but we never wrote /data/.bootstrapped, the data was created by
# something other than this script (e.g. a manually-provisioned node). In that
# case we skip restore and NEVER wipe anything.

DATA_DIR="${DATA_DIR:-/data/data}"
KEYS_DIR="${KEYS_DIR:-/data/keys}"
PHAROS_CONF="${PHAROS_CONF:-/data/pharos.conf}"
GENESIS_CONF="${GENESIS_CONF:-/data/genesis.conf}"
PUBLIC_DIR="${DATA_DIR}/public"
META_STORE="${DATA_DIR}/meta_store"
BOOTSTRAP_MARKER="/data/.bootstrapped"
INIT_MARKER="/data/.initialized"
SNAPSHOT_STAGING="/data/snapshot"

log() { echo "[pharos-init] $*"; }

fetch_version() {
  # VERSION must exist at /data/bin/VERSION before genesis: pharos_cli aborts
  # (SIGABRT in VersionManager) if it is missing.
  mkdir -p /data/bin
  wget -O /data/bin/VERSION "${VERSION_URL}"
}

fetch_configs() {
  log "Fetching genesis.conf and pharos.conf"
  wget -O "${GENESIS_CONF}" "${GENESIS_URL}"
  wget -O "${PHAROS_CONF}" "${PHAROS_CONF_URL}"
}

# Bootstrap keys + base chain data with `pharos_cli genesis`, mirroring the
# pre-genesis setup of the node's /app/docker-entrypoint.sh (pinned image).
# genesis self-terminates, so there is no node process to stop.
bootstrap_node() {
  if [ -z "${CONSENSUS_KEY_PWD:-}" ]; then
    log "ERROR: CONSENSUS_KEY_PWD is empty; cannot bootstrap. Set it in .env."
    return 1
  fi

  log "Staging node binaries (/app/bin -> /data/bin) and ops tool"
  rm -rf /data/bin.tmp
  cp -r /app/bin /data/bin.tmp
  cp /app/ops /data/ops
  chmod +x /data/ops
  # genesis requires /data/bin/VERSION; stage it into the fresh bin dir.
  fetch_version
  cp /data/bin/VERSION /data/bin.tmp/VERSION 2>/dev/null || true
  rm -rf /data/bin
  mv /data/bin.tmp /data/bin
  chmod +x /data/bin/* 2>/dev/null || true

  mkdir -p "${KEYS_DIR}"
  if [ ! -f "${KEYS_DIR}/domain.key" ] || [ ! -f "${KEYS_DIR}/stabilizing.key" ]; then
    log "Generating keys in ${KEYS_DIR}"
    /data/ops generate-keys -o "${KEYS_DIR}"
  else
    log "Found existing keys in ${KEYS_DIR}"
  fi

  log "Bootstrapping base chain data via pharos_cli genesis"
  (
    cd /data/bin
    env LD_PRELOAD=./libevmone.so \
      CONSENSUS_KEY_PWD="${CONSENSUS_KEY_PWD}" \
      PORTAL_SSL_PWD="${PORTAL_SSL_PWD:-${CONSENSUS_KEY_PWD}}" \
      ./pharos_cli genesis -c "${PHAROS_CONF}" -g "${GENESIS_CONF}"
  )

  if [ ! -d "${META_STORE}" ]; then
    log "ERROR: genesis exited 0 but ${META_STORE} was not created"
    return 1
  fi
  log "Bootstrap complete (${META_STORE} created)"
}

# Download the snapshot and swap its `public` in for the genesis-only `public`.
# Safe to wipe PUBLIC_DIR here: callers only reach this after confirming the
# current data is our own bootstrap, never external/real chain data.
download_and_swap_snapshot() {
  if [ -z "${SNAPSHOT:-}" ]; then
    log "SNAPSHOT is empty; skipping snapshot. Node will sync from genesis."
    return 0
  fi

  log "Downloading snapshot: ${SNAPSHOT}"
  mkdir -p "${SNAPSHOT_STAGING}"
  cd "${SNAPSHOT_STAGING}"
  aria2c -c -x6 -s6 --auto-file-renaming=false --conditional-get=true \
    --allow-overwrite=true -o snapshot.tar.gz "${SNAPSHOT}"

  log "Extracting snapshot"
  tar -zxvf snapshot.tar.gz
  rm -f snapshot.tar.gz

  if [ ! -d "${SNAPSHOT_STAGING}/public" ]; then
    log "ERROR: snapshot did not contain a 'public' directory; aborting before swap"
    return 1
  fi

  log "Replacing genesis 'public' with snapshot 'public'"
  rm -rf "${PUBLIC_DIR}"
  mkdir -p "${DATA_DIR}"
  mv "${SNAPSHOT_STAGING}/public" "${PUBLIC_DIR}"

  cd /data
  rm -rf "${SNAPSHOT_STAGING}"
}

restore() {
  fetch_configs

  if [ ! -f "${BOOTSTRAP_MARKER}" ]; then
    bootstrap_node
    touch "${BOOTSTRAP_MARKER}"
  else
    log "Resuming: ${BOOTSTRAP_MARKER} present, skipping bootstrap"
  fi

  download_and_swap_snapshot
  touch "${INIT_MARKER}"
  log "Initialize complete"
}

main() {
  mkdir -p /data/bin

  if [ -f "${INIT_MARKER}" ]; then
    log "Already initialized (${INIT_MARKER} present); skipping restore"
  elif [ -d "${META_STORE}" ] && [ ! -f "${BOOTSTRAP_MARKER}" ]; then
    log "WARNING: existing chain data at ${META_STORE} but no ${BOOTSTRAP_MARKER}."
    log "WARNING: treating as pre-existing/external node data."
    log "WARNING: skipping snapshot restore and NOT wiping anything."
  else
    restore
  fi

  # Always refresh the upstream VERSION file (matches prior behavior).
  fetch_version
}

main "$@"
