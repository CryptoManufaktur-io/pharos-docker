# Pharos Docker

Docker Compose for a self-hosted Pharos mainnet RPC node.

This is Pharos Docker v0.1.0

## Overview

This repo runs the official Pharos community image with the mainnet genesis,
version metadata, and full-node config from `PharosNetwork/resources`.

- HTTP RPC: `18100`
- WebSocket RPC: `18200`
- P2P TCP: `19000`
- Pharos RPC: `20000`
- Chain ID: `1672` (`0x688`)
- Default reference RPC for sync checks: `https://rpc.pharos.xyz`

The node requires a high open-file limit. Set the host kernel limit before
starting the container if it is below `10000000`:

```bash
sudo sysctl -w fs.nr_open=10000000
```

Persist that setting with your host configuration management before production
deployment.

## Quick Start

```bash
cp default.env .env
./pharosd up
```

On first startup, `./pharosd` downloads these files if they are missing:

- `data/genesis.conf`
- `data/bin/VERSION`
- `data/pharos.conf`

If `CONSENSUS_KEY_PWD` is blank in `.env`, `./pharosd up` generates a random
local value and writes it back to `.env`.

## Configuration

Key `.env` values:

| Variable | Default | Notes |
| --- | --- | --- |
| `NODE_DOCKER_REPO` | `public.ecr.aws/k2g7b7g1/pharos` | Official image repository |
| `NODE_DOCKER_TAG` | `pharos_community_v0.12.2_f301031a_0422` | Pinned image tag |
| `DATA_DIR` | `./data` | Persistent node data |
| `SNAPSHOT` | empty | Optional initial public DB snapshot |
| `SNAPSHOT_SHA256` | empty | Optional snapshot archive SHA-256 checksum |
| `SNAPSHOT_INIT_TIMEOUT` | `300` | Seconds to wait for first boot initialization |
| `RPC_PORT` | `18100` | HTTP JSON-RPC |
| `WS_PORT` | `18200` | WebSocket JSON-RPC |
| `P2P_PORT` | `19000` | P2P TCP |
| `PHAROS_RPC_PORT` | `20000` | Pharos RPC |
| `PUBLIC_RPC` | `https://rpc.pharos.xyz` | Reference endpoint for `check-sync` |

For production behind Traefik, use:

```bash
COMPOSE_FILE=pharos.yml:rpc-shared.yml:ext-network.yml
DOMAIN=cryptomanufaktur.net
RPC_HOST=pharos-a
RPC_LB=pharos-lb
WS_HOST=pharosws-a
WS_LB=pharosws-lb
```

Use the host suffix appropriate for each node, for example `pharos-a` and
`pharos-c`.

## Commands

```bash
./pharosd up
./pharosd down
./pharosd logs -f pharos
./pharosd init-logs -f
./pharosd version
./pharosd check-sync
```

`ethd` remains the canonical wrapper. `pharosd` is a symlink to `ethd`.

## Checking Sync

```bash
./pharosd check-sync
```

The sync checker:

- Verifies local `eth_chainId` is `0x688`
- Verifies the reference RPC also reports `0x688`
- Compares latest block height and hash
- Exits `0` when in sync, `1` when still syncing, and `2` on errors

Override endpoints or threshold when needed:

```bash
./pharosd check-sync --local-rpc http://127.0.0.1:18100 --public-rpc https://rpc.pharos.xyz --block-lag 10
```

## Snapshot Restore

Set `SNAPSHOT` before first start to restore an initial public DB snapshot.
Leaving `SNAPSHOT=` starts from genesis and disables snapshot restore.

Pharos must initialize its data layout before the snapshot can replace
`${DATA_DIR}/data/public`, so the wrapper does this sequence:

1. Start `pharos` once.
2. Wait until `eth_blockNumber` returns a block number.
3. Stop `pharos`.
4. Run `pharos-snapshot-init`, which downloads the snapshot with `aria2c`.
5. Replace `${DATA_DIR}/data/public` and write `${DATA_DIR}/.snapshot-restored`.
6. Start `pharos` normally.

If `${DATA_DIR}/data/public` already exists without
`${DATA_DIR}/.snapshot-init-ready`, `./pharosd up` refuses to restore
automatically. Start from a clean `DATA_DIR` for snapshot restore. Set
`SNAPSHOT=` to keep existing data and start normally.

Set `SNAPSHOT_SHA256` when a checksum is available. If set, the init container
verifies the archive before extraction. If the replacement fails, the previous
`public` directory is moved back before the script exits.

The restore runs in a screen-backed startup path like other snapshot-backed
`*-docker` repos. Follow progress with:

```bash
./pharosd init-logs -f
```

To use the BCE-10126 known-good snapshot:

```bash
SNAPSHOT=https://snapshot.dplabs-internal.com/mainnet/mainnet-snapshot-2026-04-28-06.tar.gz
```

To restore again, stop the node and remove `${DATA_DIR}/.snapshot-restored`.

## Verification

```bash
docker compose ps
docker inspect pharos-pharos --format '{{.Config.Image}}'
curl -sS -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
  http://127.0.0.1:18100
./pharosd check-sync
```
