#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
SNAPSHOT="${SNAPSHOT:-}"
MARKER="${DATA_DIR}/.snapshot-restored"
DOWNLOAD_DIR="${DATA_DIR}/snapshot"
EXTRACT_DIR="${DATA_DIR}/.snapshot-extract"
PUBLIC_DIR="${DATA_DIR}/data/public"

if [ -z "${SNAPSHOT}" ]; then
  echo "No snapshot URL defined."
  exit 0
fi

if [ -f "${MARKER}" ]; then
  echo "Snapshot already restored. Remove ${MARKER} to restore again."
  exit 0
fi

if [ ! -d "${PUBLIC_DIR}" ]; then
  echo "Pharos public data directory is missing: ${PUBLIC_DIR}"
  echo "Start Pharos once and wait for eth_blockNumber before restoring a snapshot."
  exit 1
fi

snapshot_path="${SNAPSHOT%%[?#]*}"
archive_name="${snapshot_path##*/}"
if [ -z "${archive_name}" ] || [ "${archive_name}" = "${snapshot_path}" ]; then
  archive_name="snapshot.tar.gz"
fi

archive_path="${DOWNLOAD_DIR}/${archive_name}"

mkdir -p "${DOWNLOAD_DIR}" "${EXTRACT_DIR}"
rm -rf "${EXTRACT_DIR:?}/"*

echo "Downloading snapshot with aria2c: ${SNAPSHOT}"
aria2c \
  -c \
  -x6 \
  -s6 \
  --auto-file-renaming=false \
  --conditional-get=true \
  --allow-overwrite=true \
  -d "${DOWNLOAD_DIR}" \
  -o "${archive_name}" \
  "${SNAPSHOT}"

echo "Extracting ${archive_path}"
case "${archive_name}" in
  *.tar.gz|*.tgz)
    tar -xzf "${archive_path}" -C "${EXTRACT_DIR}"
    ;;
  *.tar)
    tar -xf "${archive_path}" -C "${EXTRACT_DIR}"
    ;;
  *)
    echo "Unsupported snapshot archive format: ${archive_name}"
    exit 1
    ;;
esac

if [ -d "${EXTRACT_DIR}/public" ]; then
  snapshot_public="${EXTRACT_DIR}/public"
else
  snapshot_public="$(find "${EXTRACT_DIR}" -type d -name public -print -quit)"
fi

if [ -z "${snapshot_public:-}" ] || [ ! -d "${snapshot_public}" ]; then
  echo "Snapshot did not contain a public directory."
  exit 1
fi

backup_dir="${PUBLIC_DIR}.bak.$(date +%Y%m%d%H%M%S)"
echo "Backing up existing public data to ${backup_dir}"
mv "${PUBLIC_DIR}" "${backup_dir}"

echo "Installing snapshot public data to ${PUBLIC_DIR}"
mkdir -p "$(dirname "${PUBLIC_DIR}")"
mv "${snapshot_public}" "${PUBLIC_DIR}"

rm -rf "${EXTRACT_DIR}" "${archive_path}"
touch "${MARKER}"

echo "Snapshot restore complete."
