# amun-docker Design Specification

## Overview

amun-docker is a plugin for [amun](https://github.com/GonzaloAlvarez/amun) that installs Docker and Docker Compose across platforms. It follows the same structure and conventions as amun-update.

## Repository Structure

```
amun-docker/
├── .gitignore
├── README.md
├── ansible.cfg
├── group_vars/all.yml
├── localhost
├── main.yml
├── requirements.yml
├── test
├── spec/
│   └── DESIGN.md
└── roles/
    └── docker/
        ├── defaults/main.yml
        ├── handlers/main.yml
        ├── meta/main.yml
        ├── tasks/main.yml
        └── molecule/
            └── default/
                ├── molecule.yml
                ├── converge.yml
                └── verify.yml
```

## Conventions

- No comments in any file unless strictly necessary.
- Mirror amun-update structure and patterns exactly.
- Use `when:` conditions for platform-specific tasks (single tasks file, no per-platform includes).

## Root Configuration Files

### ansible.cfg

Identical to amun-update:

- `nocows = True`
- `collections_path = ./`
- `roles_path = ./galaxy_roles:./roles`
- `host_key_checking = false`
- `ask_vault_pass = false`
- `interpreter_python = auto_silent`
- `scp_if_ssh = True`

### localhost

```ini
[all]
127.0.0.1
```

### main.yml

```yaml
---
- hosts: all
  roles:
    - { role: docker, become: false }
```

### requirements.yml

```yaml
---
roles: []
collections:
  - name: community.general
  - name: community.docker
```

### group_vars/all.yml

Empty (or minimal docker-specific variables if needed during implementation).

## Docker Role

### Installation Tasks (roles/docker/tasks/main.yml)

#### Debian/Ubuntu

1. Install prerequisites: `ca-certificates`, `curl`, `gnupg`
2. Create `/etc/apt/keyrings` directory
3. Add Docker official GPG key from `https://download.docker.com/linux/debian/gpg` (or ubuntu)
4. Add Docker apt repository using the signed-by keyring
5. Install packages: `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-compose-plugin`
6. Enable and start the `docker` service
7. Add the current user (`{{ ansible_env.USER }}`) to the `docker` group

All apt tasks use `become: true`. Retries (5 attempts, 5-second delay) on install tasks to match amun-update's pattern for transient failures.

#### macOS (Darwin)

1. Install via Homebrew formulae: `colima`, `docker`, `docker-compose`

No `become` needed. Homebrew handles everything.

#### Arch Linux

1. Install via pacman: `docker`, `docker-compose`
2. Enable and start the `docker` service
3. Add the current user to the `docker` group

Pacman tasks use `become: true`.

#### Verification (All Platforms)

1. Run `docker --version` and assert success
2. Run `docker compose version` and assert success

### Defaults (roles/docker/defaults/main.yml)

Empty.

### Handlers (roles/docker/handlers/main.yml)

Empty.

### Meta (roles/docker/meta/main.yml)

```yaml
---
galaxy_info:
  author: Gonzalo Alvarez
  description: Install Docker and Docker Compose across platforms
  license: GPL-3.0
  min_ansible_version: "2.14"
  platforms:
    - name: Debian
      versions:
        - bookworm
    - name: Ubuntu
      versions:
        - jammy
        - noble
    - name: MacOSX
      versions:
        - all
    - name: ArchLinux
      versions:
        - all
dependencies: []
```

## Molecule Tests

### Driver

Docker (Debian-only). Testing Docker installation inside a Docker container (Docker-in-Docker). macOS and Arch are covered by the full VM-based test script.

### molecule/default/molecule.yml

- Driver: docker
- Platform: Debian Bookworm (e.g., `debian:bookworm`)
- Provisioner: ansible
- Privileged mode enabled (required for Docker-in-Docker)

### molecule/default/converge.yml

Minimal playbook that applies the `docker` role against the molecule instance.

### molecule/default/verify.yml

Runs `docker run hello-world` as the provisioned user to prove:

1. Docker is installed
2. The Docker daemon is running
3. The user has proper group permissions to use Docker without sudo

## Test Script

### Location

`amun-docker/test` (executable bash script at the repository root).

### Behavior

1. Accepts an optional platform argument (`sequoia`, `debian`, `arch`, `linux`, or no argument for all platforms)
2. Clones `https://github.com/GonzaloAlvarez/amun.git` to a temporary directory
3. Determines the absolute path of the amun-docker repository (the script's own directory)
4. Changes working directory to the cloned amun repository
5. Runs `AMUN_REPO=<amun-docker-path> ./test <platform> -p docker`
6. Cleans up the temporary directory on exit, including on SIGINT/SIGTERM via trap

### Platform Mapping

| Argument | Amun test invocation |
|----------|---------------------|
| `sequoia` or `mac` | `./test sequoia -p docker` |
| `debian` | `./test debian -p docker` |
| `arch` | `./test arch -p docker` |
| `linux` | `./test linux -p docker` |
| (none) | `./test -p docker` (all platforms) |

## Design Decisions

1. **Single role pattern**: Matches amun-update. One `docker` role with platform-conditional tasks in a single file.
2. **Colima on macOS**: Chosen over Docker Desktop (proprietary) and CLI-only (no runtime). Colima provides an open-source Docker runtime via Lima.
3. **Molecule Debian-only**: Docker-in-Docker is the only practical way to test Docker installation in molecule. macOS and Arch rely on the full VM test script.
4. **hello-world verification**: The molecule verify step runs `docker run hello-world` rather than just checking version strings. This proves the full stack works: installation, daemon, and user permissions.
5. **Test script delegates to amun**: The amun-docker test script clones the amun repository and delegates to its test infrastructure, passing amun-docker as a plugin via `AMUN_REPO`.
