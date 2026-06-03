#!/usr/bin/env bash
# Standardized sync check for Pharos JSON-RPC.
#
# Exit codes:
#   0 - In sync
#   1 - Still syncing
#   2 - Error

set -Eeuo pipefail

EXPECTED_CHAIN_ID="${EXPECTED_CHAIN_ID:-0x688}"
DEFAULT_LOCAL_RPC="http://127.0.0.1:${RPC_PORT:-18100}"
DEFAULT_PUBLIC_RPC="${PUBLIC_RPC:-https://rpc.pharos.xyz}"
BLOCK_LAG_THRESHOLD="${BLOCK_LAG_THRESHOLD:-5}"
ENV_FILE="${ENV_FILE:-.env}"
LOCAL_RPC=""
PUBLIC_RPC=""
CONTAINER=""
COMPOSE_SERVICE=""
INSTALL_TOOLS=1

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Check Pharos node sync status against a reference RPC.

Options:
  --container NAME         Docker container name or ID to run curl/jq within
  --compose-service NAME   Docker Compose service name to resolve to a container
  --local-rpc URL          Local RPC URL (default: $DEFAULT_LOCAL_RPC)
  --public-rpc URL         Reference RPC URL (default: $DEFAULT_PUBLIC_RPC)
  --block-lag N            Acceptable lag in blocks (default: $BLOCK_LAG_THRESHOLD)
  --no-install             Do not install curl/jq inside the container
  --env-file PATH          Path to env file to load (default: $ENV_FILE)
  -h, --help               Show this help

Exit codes:
  0 - In sync
  1 - Still syncing
  2 - Error
EOF
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

load_env_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ -z "$line" || "$line" == \#* ]] && continue
    line="${line#export }"
    line="$(trim "$line")"

    if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      local key="${line%%=*}"
      local val="${line#*=}"
      key="$(trim "$key")"
      val="$(trim "$val")"

      if [[ "$val" == \"*\" && "$val" == *\" ]]; then
        val="${val:1:-1}"
      elif [[ "$val" == \'*\' && "$val" == *\' ]]; then
        val="${val:1:-1}"
      fi

      export "$key=$val"
    fi
  done < "$file"
}

error_exit() {
  echo "❌ error: $1" >&2
  echo >&2
  echo "❌ Final status: error" >&2
  exit 2
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --container|--compose-service|--local-rpc|--public-rpc|--block-lag|--env-file)
        if [[ $# -lt 2 ]]; then
          error_exit "$1 requires a value"
        fi
        ;;
    esac

    case "$1" in
      --container)
        CONTAINER="$2"
        shift 2
        ;;
      --compose-service)
        COMPOSE_SERVICE="$2"
        shift 2
        ;;
      --local-rpc)
        LOCAL_RPC="$2"
        shift 2
        ;;
      --public-rpc)
        PUBLIC_RPC="$2"
        shift 2
        ;;
      --block-lag)
        BLOCK_LAG_THRESHOLD="$2"
        shift 2
        ;;
      --env-file)
        ENV_FILE="$2"
        shift 2
        ;;
      --no-install)
        INSTALL_TOOLS=0
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        error_exit "unknown option: $1"
        ;;
    esac
  done
}

resolve_container() {
  if [[ -n "$CONTAINER" || -z "$COMPOSE_SERVICE" ]]; then
    return 0
  fi
  if ! command -v docker >/dev/null 2>&1; then
    error_exit "docker not found; cannot resolve --compose-service $COMPOSE_SERVICE"
  fi

  CONTAINER="$(docker compose ps -q "$COMPOSE_SERVICE" 2>/dev/null | head -n 1 || true)"
  if [[ -z "$CONTAINER" ]]; then
    error_exit "no running container found for service: $COMPOSE_SERVICE"
  fi
}

check_tools() {
  if [[ -n "$CONTAINER" ]]; then
    echo "⏳ Checking tools inside container"
    if [[ "$INSTALL_TOOLS" == "1" ]]; then
      docker exec -u root "$CONTAINER" sh -c '
        set -e
        if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
          exit 0
        fi
        if command -v apt-get >/dev/null 2>&1; then
          apt-get update -y >/dev/null
          apt-get install -y curl jq ca-certificates >/dev/null
        elif command -v apk >/dev/null 2>&1; then
          apk add --no-cache curl jq ca-certificates >/dev/null
        elif command -v yum >/dev/null 2>&1; then
          yum install -y curl jq ca-certificates >/dev/null
        elif command -v dnf >/dev/null 2>&1; then
          dnf install -y curl jq ca-certificates >/dev/null
        else
          echo "unsupported base image: no apt-get, apk, yum, or dnf"
          exit 1
        fi
      ' || error_exit "curl/jq are unavailable in container"
    else
      docker exec "$CONTAINER" sh -c 'command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1' \
        || error_exit "curl/jq are unavailable in container"
    fi
    echo "✅ Tools available in container"
  else
    echo "⏳ Checking tools on host"
    command -v curl >/dev/null 2>&1 || error_exit "curl is required on the host"
    command -v jq >/dev/null 2>&1 || error_exit "jq is required on the host"
    echo "✅ Tools available on host"
  fi
}

rpc_post() {
  local url="$1"
  local payload="$2"

  if [[ -n "$CONTAINER" ]]; then
    docker exec "$CONTAINER" curl -fsS --max-time 20 \
      -H "Content-Type: application/json" \
      --data "$payload" \
      "$url"
  else
    curl -fsS --max-time 20 \
      -H "Content-Type: application/json" \
      --data "$payload" \
      "$url"
  fi
}

jq_read() {
  local filter="$1"
  local json="$2"

  if [[ -n "$CONTAINER" ]]; then
    printf '%s' "$json" | docker exec -i "$CONTAINER" jq -r "$filter"
  else
    printf '%s' "$json" | jq -r "$filter"
  fi
}

hex_to_dec() {
  local hex="$1"
  hex="${hex#0x}"
  printf '%d' "$((16#$hex))"
}

get_chain_id() {
  local url="$1"
  local label="$2"
  local response
  local result
  local rc

  set +e
  response="$(rpc_post "$url" '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}')"
  rc=$?
  set -e
  (( rc == 0 )) || error_exit "$label RPC unreachable ($url)"

  set +e
  result="$(jq_read '.result // empty' "$response")"
  rc=$?
  set -e
  (( rc == 0 )) || error_exit "$label RPC returned invalid JSON"

  [[ -n "$result" && "$result" != "null" ]] || error_exit "$label RPC did not return eth_chainId"
  printf '%s' "$result"
}

get_latest_block() {
  local url="$1"
  local label="$2"
  local response
  local number
  local hash
  local rc

  set +e
  response="$(rpc_post "$url" '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}')"
  rc=$?
  set -e
  (( rc == 0 )) || error_exit "$label RPC latest block request failed ($url)"

  set +e
  number="$(jq_read '.result.number // empty' "$response")"
  rc=$?
  set -e
  (( rc == 0 )) || error_exit "$label RPC returned invalid block JSON"

  set +e
  hash="$(jq_read '.result.hash // empty' "$response")"
  rc=$?
  set -e
  (( rc == 0 )) || error_exit "$label RPC returned invalid block JSON"

  [[ -n "$number" && "$number" != "null" ]] || error_exit "$label RPC did not return latest block number"
  [[ -n "$hash" && "$hash" != "null" ]] || error_exit "$label RPC did not return latest block hash"

  printf '%s\t%s\n' "$(hex_to_dec "$number")" "$hash"
}

main() {
  parse_args "$@"
  load_env_file "$ENV_FILE"

  EXPECTED_CHAIN_ID="${EXPECTED_CHAIN_ID:-0x688}"
  LOCAL_RPC="${LOCAL_RPC:-http://127.0.0.1:${RPC_PORT:-18100}}"
  PUBLIC_RPC="${PUBLIC_RPC:-${DEFAULT_PUBLIC_RPC}}"
  BLOCK_LAG_THRESHOLD="${BLOCK_LAG_THRESHOLD:-5}"

  [[ -n "$PUBLIC_RPC" ]] || error_exit "PUBLIC_RPC is required"
  [[ "$BLOCK_LAG_THRESHOLD" =~ ^[0-9]+$ ]] || error_exit "--block-lag must be a non-negative integer"

  resolve_container
  check_tools
  echo

  local local_chain_id
  local public_chain_id
  local local_block
  local public_block
  local local_height
  local public_height
  local local_hash
  local public_hash
  local lag
  local direction

  local_chain_id="$(get_chain_id "$LOCAL_RPC" "local")"
  if [[ "$local_chain_id" != "$EXPECTED_CHAIN_ID" ]]; then
    error_exit "local eth_chainId is $local_chain_id, expected $EXPECTED_CHAIN_ID"
  fi

  public_chain_id="$(get_chain_id "$PUBLIC_RPC" "public")"
  if [[ "$public_chain_id" != "$EXPECTED_CHAIN_ID" ]]; then
    error_exit "public eth_chainId is $public_chain_id, expected $EXPECTED_CHAIN_ID"
  fi

  echo "⏳ Latest block comparison"
  local_block="$(get_latest_block "$LOCAL_RPC" "local")"
  public_block="$(get_latest_block "$PUBLIC_RPC" "public")"

  local_height="${local_block%%$'\t'*}"
  local_hash="${local_block#*$'\t'}"
  public_height="${public_block%%$'\t'*}"
  public_hash="${public_block#*$'\t'}"

  printf 'Local latest:  %s %s\n' "$local_height" "$local_hash"
  printf 'Public latest: %s %s\n' "$public_height" "$public_hash"

  if (( public_height > local_height )); then
    lag=$((public_height - local_height))
    direction="local behind"
  elif (( local_height > public_height )); then
    lag=0
    direction="local ahead"
  else
    lag=0
    direction="in sync"
  fi

  printf 'Lag:         %s blocks (threshold: %s) (%s)\n' "$lag" "$BLOCK_LAG_THRESHOLD" "$direction"
  echo

  if (( local_height == public_height )) && [[ "$local_hash" != "$public_hash" ]]; then
    echo "❌ Final status: error"
    exit 2
  fi

  if (( lag > BLOCK_LAG_THRESHOLD )); then
    echo "⏳ Final status: syncing"
    exit 1
  fi

  echo "✅ Final status: in sync"
  exit 0
}

main "$@"
