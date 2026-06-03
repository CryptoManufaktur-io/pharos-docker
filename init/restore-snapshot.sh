#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
SNAPSHOT="${SNAPSHOT:-}"
SNAPSHOT_SHA256="${SNAPSHOT_SHA256:-}"
MARKER="${DATA_DIR}/.snapshot-restored"
DOWNLOAD_DIR="${DATA_DIR}/snapshot"
EXTRACT_DIR="${DATA_DIR}/.snapshot-extract"
PUBLIC_DIR="${DATA_DIR}/data/public"
backup_dir=""
restore_in_progress=0

rollback_restore() {
  local exit_code=$?

  if [ "${restore_in_progress}" -eq 1 ]; then
    echo "Snapshot restore failed. Rolling back ${PUBLIC_DIR}."
    rm -rf "${PUBLIC_DIR}"
    if [ -n "${backup_dir}" ] && [ -d "${backup_dir}" ]; then
      mv "${backup_dir}" "${PUBLIC_DIR}"
    fi
  fi

  exit "${exit_code}"
}

trap rollback_restore ERR

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

if [ -n "${SNAPSHOT_SHA256}" ]; then
  echo "Verifying snapshot checksum."
  actual_sha256="$(sha256sum "${archive_path}" | awk '{print $1}')"
  if [ "${actual_sha256}" != "${SNAPSHOT_SHA256}" ]; then
    echo "Snapshot checksum mismatch."
    echo "Expected: ${SNAPSHOT_SHA256}"
    echo "Actual:   ${actual_sha256}"
    exit 1
  fi
fi

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

if [ -z "$(find "${snapshot_public}" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
  echo "Snapshot public directory is empty."
  exit 1
fi

backup_dir="${PUBLIC_DIR}.bak.$(date +%Y%m%d%H%M%S)"
echo "Backing up existing public data to ${backup_dir}"
restore_in_progress=1
mv "${PUBLIC_DIR}" "${backup_dir}"

echo "Installing snapshot public data to ${PUBLIC_DIR}"
mkdir -p "$(dirname "${PUBLIC_DIR}")"
mv "${snapshot_public}" "${PUBLIC_DIR}"

if [ -z "$(find "${PUBLIC_DIR}" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
  echo "Restored public directory is empty."
  exit 1
fi

restore_in_progress=0
trap - ERR

rm -rf "${EXTRACT_DIR}" "${archive_path}"
touch "${MARKER}"

echo "Snapshot restore complete."
