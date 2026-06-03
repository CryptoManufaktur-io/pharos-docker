#!/bin/sh
set -eu

LOG_DIR="${LOG_DIR:-/data/log}"
LOG_ROTATION_KEEP="${LOG_ROTATION_KEEP:-10}"
LOG_PRUNE_INTERVAL="${LOG_PRUNE_INTERVAL:-3600}"

case "${LOG_ROTATION_KEEP}" in
  ''|*[!0-9]*)
    echo "LOG_ROTATION_KEEP must be a non-negative integer."
    exit 1
    ;;
esac

case "${LOG_PRUNE_INTERVAL}" in
  ''|*[!0-9]*)
    echo "LOG_PRUNE_INTERVAL must be a non-negative integer."
    exit 1
    ;;
esac

prune_once() {
  removed=0
  freed=0

  if [ ! -d "${LOG_DIR}" ]; then
    echo "Pharos log directory does not exist yet: ${LOG_DIR}"
    return 0
  fi

  for file in "${LOG_DIR}"/*.[0-9]*.log; do
    [ -e "${file}" ] || continue

    base="${file##*/}"
    suffix="${base%.log}"
    suffix="${suffix##*.}"

    case "${suffix}" in
      ''|*[!0-9]*)
        continue
        ;;
    esac

    if [ "${suffix}" -gt "${LOG_ROTATION_KEEP}" ]; then
      size="$(wc -c < "${file}" 2>/dev/null | tr -d ' ' || printf '0')"
      rm -f -- "${file}"
      removed=$((removed + 1))
      freed=$((freed + size))
    fi
  done

  echo "Pruned Pharos rotated logs: dir=${LOG_DIR} keep=${LOG_ROTATION_KEEP} removed=${removed} freed_bytes=${freed}"
}

if [ "${1:-}" = "--once" ] || [ "${LOG_PRUNE_ONCE:-0}" = "1" ]; then
  prune_once
  exit 0
fi

while true; do
  prune_once
  sleep "${LOG_PRUNE_INTERVAL}"
done
