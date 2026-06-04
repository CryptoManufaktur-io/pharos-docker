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

On first startup, a one-shot `init` service runs automatically before the node;
the `pharos` service waits for it via `depends_on: service_completed_successfully`.
The init service stages everything the node needs into the `data` volume and
performs the full snapshot restore headlessly (see [Snapshot Restore](#snapshot-restore)),
then writes a `data/.initialized` marker so later restarts skip the work.

If `CONSENSUS_KEY_PWD` is blank in `.env`, `./pharosd up` generates a random
local value and writes it back to `.env`.

## Configuration

Key `.env` values:

| Variable | Default | Notes |
| --- | --- | --- |
| `NODE_DOCKER_REPO` | `public.ecr.aws/k2g7b7g1/pharos` | Official image repository |
| `NODE_DOCKER_TAG` | `pharos_community_v0.12.2_f301031a_0422` | Pinned image tag |
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

Snapshot restore is fully automated by the one-shot `init` service and runs on
first start only. Set `SNAPSHOT` in `.env` to the snapshot archive URL before
`./pharosd up`.

The Pharos snapshot archive contains only the `public` chain database, and the
node must generate its keys and bootstrap its base chain data *before* that
`public` can be swapped in. The init service does this headlessly, in order:

1. Fetch `genesis.conf`, `pharos.conf`, and `bin/VERSION`.
2. **Bootstrap**: generate `data/keys` and the base `data/data` chain dirs
   (`meta_store`, `public`, ...) by running `pharos_cli genesis`, which exits on
   its own. Marker: `data/.bootstrapped`.
3. **Snapshot**: download `SNAPSHOT` (resumable, via `aria2c`), extract it, and
   replace the freshly-bootstrapped `data/data/public` with the snapshot's
   `public`. Marker: `data/.initialized`.

The `pharos` service then starts and syncs forward from the snapshot height.
Later restarts short-circuit on `data/.initialized`.

**Safety:** the init service never wipes existing chain data it did not create.
If `data/data/meta_store` exists without a `data/.bootstrapped` marker (for
example a node that was provisioned manually), the init service logs a warning
and skips the restore entirely rather than destroying the node's data.

`default.env` ships the current mainnet snapshot URL, for example:

```text
SNAPSHOT=https://snapshot.dplabs-internal.com/mainnet/mainnet-snapshot-2026-06-01-03.tar.gz
```

To restore from a newer snapshot later, update `SNAPSHOT`, remove both the
`data/.initialized` and `data/.bootstrapped` markers and the stale
`data/data/public` directory inside the `data` volume, then run `./pharosd up`
again so `init` re-runs.

## Verification

```bash
docker compose ps
docker inspect pharos-pharos --format '{{.Config.Image}}'
curl -sS -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
  http://127.0.0.1:18100
./pharosd check-sync
```
