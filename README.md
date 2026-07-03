# Amun Docker

**amun-docker** is a plugin for [amun](https://github.com/GonzaloAlvarez/amun) that installs Docker and Docker Compose across platforms.

---

## Usage

Run the docker plugin through amun:

```bash
amun docker
```

## Supported Platforms

| Platform | Method | Packages |
|----------|--------|----------|
| Debian/Ubuntu | Docker official apt repo | docker-ce, docker-ce-cli, containerd.io, docker-compose-plugin |
| macOS | Homebrew | colima, docker, docker-compose |
| Arch Linux | pacman | docker, docker-compose |

## Stack resiliency (Linux)

On an ungraceful reboot Docker loses its restart-manager state, so `restart:
unless-stopped` alone leaves some containers Exited and never restarted. To fix
this consistently, `amun-docker` discovers `cn-*` docker-compose stacks under the
deploy user's `~` and `~/dev` and, for each stack that ships a **`resiliency.yml`**
manifest, installs:

- a **`docker-compose@<stack>.service`** systemd boot unit — runs `docker compose
  up -d` at boot regardless of Docker's restart state (optionally NFS-mount-gated
  + ordered);
- an **`/etc/cron.d/<stack>-reconcile`** job that runs the shared
  `/usr/local/lib/amun/reconcile-stack.sh`, which repairs the three states
  Docker's restart policy misses — **Exited** service containers (start them),
  **netns drift** and **stuck-unhealthy** (force-recreate) — and writes
  node-exporter textfile metrics (`resilience_reconcile_*`) so execution is
  observable in the "Resilience" Grafana dashboard.

Re-running `amun docker` after stacks are cloned installs/updates these
idempotently. Stacks without a `resiliency.yml` are skipped.

### `resiliency.yml` manifest

```yaml
project: cn-media          # optional; default = repo dir basename (compose -p)
working_dir: /opt/cloudnet # optional; where `docker compose` runs. Default = the
                           #   discovered dir. Override for a stack deployed away
                           #   from its repo — e.g. a stub ~/cn-<x> dir (which the
                           #   cn-* discovery finds) pointing at /opt/<x>.
boot:
  enabled: true
  nfs_mount: /path/to/nfs  # optional → RequiresMountsFor + mountpoint/stat-f nfs precheck
  binds_to_mount: true     # optional → BindsTo the derived .mount unit (tear the
                           #   stack down if the NFS mount itself fails, rather than
                           #   leaving it bound to the empty local placeholder dir)
  require_paths:           # optional → ExecStartPre `test -d` for each subtree
    - /path/to/nfs/movies  #   (bail before compose sees a missing bind source)
  after: [cn-bittorrent]   # optional → serial boot ordering (other stacks)
  force_recreate: false    # optional → `up -d --force-recreate` on boot
reconcile:
  enabled: true
  schedule: "*/5 * * * *"  # cron.d schedule for the reconcile helper
cron:                      # optional stack-specific periodic scripts (in scripts/)
  - { name: prune, schedule: "0 4 * * *", script: scripts/prune.sh }
```

Verify an installed host with the Layer-4 script: `./verify` (local) or
`./verify --host <host> --user <user>`.

## Testing

Run the test script to validate across platforms:

```bash
./test              # all platforms
./test debian       # debian only
./test sequoia      # macOS only
./test arch         # arch only
```

## License

GNU GENERAL PUBLIC LICENSE
Version 3, 29 June 2007

Copyright (c) 2025 Gonzalo Alvarez
