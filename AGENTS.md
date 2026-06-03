# AGENTS.md - Pharos Docker instructions

See README.md for project overview, setup, snapshot behavior, and operational verification.
See CONTRIBUTING.md for contribution expectations.

## Project Structure

- `ethd` is the canonical wrapper; `pharosd` must remain a symlink to `ethd`.
- `pharos.yml` defines `pharos` and `pharos-snapshot-init`.
- `rpc-shared.yml` and `ext-network.yml` add RPC and Traefik exposure.
- `scripts/check_sync.sh` is the EVM JSON-RPC sync checker.
- `init/restore-snapshot.sh` is the snapshot restore entrypoint.

## Build & Validation

```bash
shellcheck -x ethd scripts/check_sync.sh
shellcheck -x init/restore-snapshot.sh
pre-commit run --all-files
./pharosd help
./pharosd -h
./pharosd check-sync -h
CONSENSUS_KEY_PWD=test docker compose --env-file default.env --profile snapshot config
```

## Code Style

- Keep shell scripts POSIX-friendly where practical, but `ethd` and restore scripts may use Bash.
- Keep comments short and only where they prevent operational mistakes.

## Testing

- `./pharosd check-sync` may fail with a local RPC error when the node is not running; it must not fail from env parsing or missing defaults.
- Validate compose output includes ports `18100`, `18200`, `19000`, `20000`, and `nofile` `10000000`.

## Critical Rules

- Keep `NODE_DOCKER_TAG` pinned. Do not use `latest`.
- Keep Pharos mainnet chain ID set to `0x688`.
- `./pharosd up` must fetch `genesis.conf`, `bin/VERSION`, and `pharos.conf` if missing.
- `SNAPSHOT` restore must use `pharos-snapshot-init` and `aria2c`.
- `SNAPSHOT=` must disable restore; do not fall back to `default.env` for an explicit blank value.
- `./pharosd up` must initialize Pharos before replacing `${DATA_DIR}/data/public`.
- Refuse automatic restore when `${DATA_DIR}/data/public` exists without `${DATA_DIR}/.snapshot-init-ready`.
- Keep long snapshot restore work in the screen-backed startup path.
- `CONSENSUS_KEY_PWD` must not stay blank at container startup.
- Preserve the `nofile` ulimit of `10000000`.
- Do not commit `.env`, `data/`, snapshots, generated keys, or restored chain data.
