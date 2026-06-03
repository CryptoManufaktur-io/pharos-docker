# CLAUDE.md - Pharos Docker instructions

See README.md for project overview, setup, and operational verification.

## Build And Validate

```bash
shellcheck -x ethd scripts/check_sync.sh
pre-commit run --all-files
./pharosd help
./pharosd -h
cp default.env .env && ./pharosd check-sync
shellcheck -x init/restore-snapshot.sh
docker compose --env-file default.env --profile snapshot config
```

The last command is expected to fail with a local RPC error if the node is not
running. It should not fail from env parsing or missing defaults.

## Critical Rules

- Keep `NODE_DOCKER_TAG` pinned. Do not use `latest`.
- Keep Pharos mainnet chain ID set to `0x688`.
- Keep `ethd` as the canonical wrapper and `pharosd` as the convenience symlink.
- `./pharosd up` must fetch `genesis.conf`, `bin/VERSION`, and `pharos.conf` if missing.
- `SNAPSHOT` restore must use `pharos-snapshot-init` and `aria2c`.
- `./pharosd up` must initialize Pharos before replacing `${DATA_DIR}/data/public`.
- Keep long snapshot restore work in the screen-backed startup path.
- `CONSENSUS_KEY_PWD` must not stay blank at container startup.
- Preserve the `nofile` ulimit of `10000000`.
- Do not commit `.env`, `data/`, snapshots, generated keys, or restored chain data.

## Production Notes

For Chainlink RPC deployment, production inventory should set:

```bash
COMPOSE_FILE=pharos.yml:rpc-shared.yml:ext-network.yml
DOMAIN=cryptomanufaktur.net
RPC_LB=pharos-lb
WS_LB=pharosws-lb
```

Use per-host `RPC_HOST` and `WS_HOST` values such as `pharos-a`,
`pharosws-a`, `pharos-c`, and `pharosws-c`.
