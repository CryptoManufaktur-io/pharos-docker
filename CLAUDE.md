# CLAUDE.md - Pharos Docker instructions

See README.md for project overview, setup, configuration (including the
production/Traefik values), and operational verification.

## Build And Validate

```bash
shellcheck -x ethd scripts/check_sync.sh init/fetch-snapshot.sh
pre-commit run --all-files
./pharosd help
./pharosd -h
cp default.env .env && ./pharosd check-sync
```

The last command is expected to fail with a local RPC error if the node is not
running. It should not fail from env parsing or missing defaults.

## Critical Rules

- Keep `NODE_DOCKER_TAG` pinned. Do not use `latest`.
- Keep Pharos mainnet chain ID set to `0x688`.
- Keep `ethd` as the canonical wrapper and `pharosd` as the convenience symlink.
- `./pharosd up` must fetch `genesis.conf`, `bin/VERSION`, and `pharos.conf` if missing.
- `CONSENSUS_KEY_PWD` must not stay blank at container startup.
- Preserve the `nofile` ulimit of `10000000` on **both** the `pharos` and `init`
  services (the `init` service runs the node to bootstrap, so it needs it too).
- Do not commit `.env`, `data/`, snapshots, generated keys, or restored chain data.

### Snapshot restore (init/fetch-snapshot.sh)

- The snapshot archive holds only the `public` DB. Restore order is mandatory:
  bootstrap the node first (it generates keys + base chain data), then swap in
  the snapshot's `public`. Do not move the snapshot into a bare volume.
- `/data/bin/VERSION` MUST exist before bootstrap. `pharos_cli genesis` aborts
  (SIGABRT) in `VersionManager` if it is missing, so fetch it in `fetch_configs`
  before running the node, not just at the end.
- Bootstrap also needs the `nofile=10000000` ulimit, or genesis storage init
  aborts with `letus ... "fd limit exceeded, error 24"` (EMFILE).
- Marker contract: `data/.bootstrapped` = we ran the node once; `data/.initialized`
  = snapshot swapped in. `.initialized` must be the last write of a successful run.
- Never wipe chain data the script did not create. If `data/data/meta_store`
  exists without `data/.bootstrapped`, treat it as external/real data: skip
  restore, do not wipe. The only `public` ever removed is our own genesis bootstrap.
