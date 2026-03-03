# amun-docker Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create an amun plugin that installs Docker and Docker Compose across Debian, macOS, and Arch Linux, with molecule verification and a delegating test script.

**Architecture:** Single Ansible role (`docker`) mirroring amun-update's structure. Platform-conditional tasks in one file using `when:` guards. Molecule tests validate Debian path with Docker-in-Docker. A root `test` script clones the amun repo and delegates to its VM-based test infrastructure.

**Tech Stack:** Ansible, Molecule (Docker driver), Bash, community.general and community.docker collections.

**Convention:** No comments in any file unless strictly necessary. All Ansible files use `---` YAML document start marker only.

**Reference:** Full design spec at `spec/DESIGN.md`.

---

### Task 1: Initialize Git Repository

**Files:**
- Create: `amun-docker/` (already exists at `/Users/galvarez/dev/amun-docker/`)

**Step 1: Initialize git repo**

Run:
```bash
cd /Users/galvarez/dev/amun-docker && git init
```

**Step 2: Commit**

```bash
git add -A && git commit -m "chore: initialize amun-docker repository"
```

---

### Task 2: Create Root Configuration Files

**Files:**
- Create: `ansible.cfg`
- Create: `localhost`
- Create: `main.yml`
- Create: `requirements.yml`
- Create: `group_vars/all.yml`
- Create: `.gitignore`

**Step 1: Create ansible.cfg**

```ini
[defaults]

nocows = True

collections_path = ./

roles_path = ./galaxy_roles:./roles

host_key_checking = false

ask_vault_pass = false

interpreter_python = auto_silent
[ssh_connection]
scp_if_ssh=True
```

**Step 2: Create localhost**

```ini
[all]
127.0.0.1
```

**Step 3: Create main.yml**

```yaml
---
- hosts: all
  roles:
    - { role: docker, become: false }
```

**Step 4: Create requirements.yml**

```yaml
---
roles: []
collections:
  - name: community.general
  - name: community.docker
```

**Step 5: Create group_vars/all.yml**

```yaml
---
```

**Step 6: Create .gitignore**

```
galaxy_roles/
ansible_collections/
```

**Step 7: Validate ansible config parses**

Run:
```bash
cd /Users/galvarez/dev/amun-docker && ansible --version
```
Expected: Ansible version output, no errors.

**Step 8: Commit**

```bash
git add ansible.cfg localhost main.yml requirements.yml group_vars/all.yml .gitignore
git commit -m "feat: add root ansible configuration files"
```

---

### Task 3: Create Docker Role Skeleton

**Files:**
- Create: `roles/docker/defaults/main.yml`
- Create: `roles/docker/handlers/main.yml`
- Create: `roles/docker/meta/main.yml`
- Create: `roles/docker/tasks/main.yml` (empty placeholder)

**Step 1: Create directory structure**

Run:
```bash
mkdir -p /Users/galvarez/dev/amun-docker/roles/docker/{defaults,handlers,meta,tasks}
```

**Step 2: Create defaults/main.yml**

```yaml
---
```

**Step 3: Create handlers/main.yml**

```yaml
---
```

**Step 4: Create meta/main.yml**

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

**Step 5: Create tasks/main.yml (empty placeholder)**

```yaml
---
```

**Step 6: Validate playbook syntax**

Run:
```bash
cd /Users/galvarez/dev/amun-docker && ansible-playbook --syntax-check -i localhost main.yml
```
Expected: `playbook: main.yml` with no errors.

**Step 7: Commit**

```bash
git add roles/
git commit -m "feat: add docker role skeleton with metadata"
```

---

### Task 4: Implement Debian Installation Tasks

**Files:**
- Modify: `roles/docker/tasks/main.yml`

**Step 1: Write the Debian tasks**

Add to `roles/docker/tasks/main.yml`:

```yaml
---
- name: Install Docker prerequisites (Debian)
  apt:
    name:
      - ca-certificates
      - curl
      - gnupg
    state: present
    update_cache: yes
  become: true
  retries: 5
  delay: 5
  register: result
  until: result is not failed
  when: ansible_facts['os_family'] == 'Debian'

- name: Create apt keyrings directory (Debian)
  file:
    path: /etc/apt/keyrings
    state: directory
    mode: "0755"
  become: true
  when: ansible_facts['os_family'] == 'Debian'

- name: Add Docker GPG key (Debian)
  get_url:
    url: "https://download.docker.com/linux/{{ ansible_facts['distribution'] | lower }}/gpg"
    dest: /etc/apt/keyrings/docker.asc
    mode: "0644"
  become: true
  when: ansible_facts['os_family'] == 'Debian'

- name: Add Docker apt repository (Debian)
  apt_repository:
    repo: "deb [arch={{ ansible_facts['architecture'] | replace('x86_64', 'amd64') | replace('aarch64', 'arm64') }} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/{{ ansible_facts['distribution'] | lower }} {{ ansible_facts['distribution_release'] }} stable"
    state: present
  become: true
  when: ansible_facts['os_family'] == 'Debian'

- name: Install Docker packages (Debian)
  apt:
    name:
      - docker-ce
      - docker-ce-cli
      - containerd.io
      - docker-compose-plugin
    state: present
    update_cache: yes
  become: true
  retries: 5
  delay: 5
  register: result
  until: result is not failed
  when: ansible_facts['os_family'] == 'Debian'

- name: Enable and start Docker service (Debian)
  systemd:
    name: docker
    enabled: true
    state: started
  become: true
  when: ansible_facts['os_family'] == 'Debian'

- name: Add user to docker group (Debian)
  user:
    name: "{{ ansible_env.USER }}"
    groups: docker
    append: true
  become: true
  when: ansible_facts['os_family'] == 'Debian'
```

**Step 2: Validate syntax**

Run:
```bash
cd /Users/galvarez/dev/amun-docker && ansible-playbook --syntax-check -i localhost main.yml
```
Expected: No errors.

**Step 3: Commit**

```bash
git add roles/docker/tasks/main.yml
git commit -m "feat: add Debian Docker installation tasks"
```

---

### Task 5: Implement macOS Installation Tasks

**Files:**
- Modify: `roles/docker/tasks/main.yml`

**Step 1: Append macOS tasks to tasks/main.yml**

Append after the Debian tasks:

```yaml
- name: Install Docker via Homebrew (macOS)
  community.general.homebrew:
    name:
      - colima
      - docker
      - docker-compose
    state: present
  when: ansible_facts['os_family'] == 'Darwin'
```

**Step 2: Validate syntax**

Run:
```bash
cd /Users/galvarez/dev/amun-docker && ansible-playbook --syntax-check -i localhost main.yml
```
Expected: No errors.

**Step 3: Commit**

```bash
git add roles/docker/tasks/main.yml
git commit -m "feat: add macOS Docker installation tasks (colima)"
```

---

### Task 6: Implement Arch Linux Installation Tasks

**Files:**
- Modify: `roles/docker/tasks/main.yml`

**Step 1: Append Arch tasks to tasks/main.yml**

Append after the macOS tasks:

```yaml
- name: Install Docker packages (Arch)
  community.general.pacman:
    name:
      - docker
      - docker-compose
    state: present
    update_cache: yes
  become: true
  when: ansible_facts['os_family'] == 'Archlinux'

- name: Enable and start Docker service (Arch)
  systemd:
    name: docker
    enabled: true
    state: started
  become: true
  when: ansible_facts['os_family'] == 'Archlinux'

- name: Add user to docker group (Arch)
  user:
    name: "{{ ansible_env.USER }}"
    groups: docker
    append: true
  become: true
  when: ansible_facts['os_family'] == 'Archlinux'
```

**Step 2: Validate syntax**

Run:
```bash
cd /Users/galvarez/dev/amun-docker && ansible-playbook --syntax-check -i localhost main.yml
```
Expected: No errors.

**Step 3: Commit**

```bash
git add roles/docker/tasks/main.yml
git commit -m "feat: add Arch Linux Docker installation tasks"
```

---

### Task 7: Add Verification Tasks

**Files:**
- Modify: `roles/docker/tasks/main.yml`

**Step 1: Append verification tasks to tasks/main.yml**

Append after all platform-specific tasks:

```yaml
- name: Verify Docker installation
  command: docker --version
  changed_when: false

- name: Verify Docker Compose installation
  command: docker compose version
  changed_when: false
```

**Step 2: Validate syntax**

Run:
```bash
cd /Users/galvarez/dev/amun-docker && ansible-playbook --syntax-check -i localhost main.yml
```
Expected: No errors.

**Step 3: Commit**

```bash
git add roles/docker/tasks/main.yml
git commit -m "feat: add Docker verification tasks"
```

---

### Task 8: Create Molecule Test Structure

**Files:**
- Create: `roles/docker/molecule/default/molecule.yml`
- Create: `roles/docker/molecule/default/converge.yml`
- Create: `roles/docker/molecule/default/verify.yml`

**Step 1: Create molecule directory**

Run:
```bash
mkdir -p /Users/galvarez/dev/amun-docker/roles/docker/molecule/default
```

**Step 2: Create molecule.yml**

```yaml
---
driver:
  name: docker
platforms:
  - name: docker-test
    image: debian:bookworm
    privileged: true
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
    cgroupns_mode: host
    command: /sbin/init
    pre_build_image: true
provisioner:
  name: ansible
verifier:
  name: ansible
```

**Step 3: Create converge.yml**

```yaml
---
- name: Converge
  hosts: all
  roles:
    - role: docker
```

**Step 4: Create verify.yml**

```yaml
---
- name: Verify
  hosts: all
  tasks:
    - name: Run hello-world container
      command: docker run hello-world
      register: hello_world
      changed_when: false

    - name: Verify hello-world output
      assert:
        that:
          - hello_world.rc == 0
          - "'Hello from Docker!' in hello_world.stdout"
```

**Step 5: Commit**

```bash
git add roles/docker/molecule/
git commit -m "feat: add molecule tests with hello-world verification"
```

---

### Task 9: Create Test Script

**Files:**
- Create: `test` (executable)

**Step 1: Write the test script**

```bash
#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AMUN_TMPDIR=$(mktemp -d)
PLATFORM="${1:-}"

trap 'rm -rf "$AMUN_TMPDIR"' EXIT SIGINT SIGTERM

git clone https://github.com/GonzaloAlvarez/amun.git "$AMUN_TMPDIR/amun"

if [ -n "$PLATFORM" ]; then
    AMUN_REPO="$SCRIPT_DIR" "$AMUN_TMPDIR/amun/test" "$PLATFORM" -p docker
else
    AMUN_REPO="$SCRIPT_DIR" "$AMUN_TMPDIR/amun/test" -p docker
fi
```

**Step 2: Make executable**

Run:
```bash
chmod +x /Users/galvarez/dev/amun-docker/test
```

**Step 3: Commit**

```bash
git add test
git commit -m "feat: add test script delegating to amun test infrastructure"
```

---

### Task 10: Create README

**Files:**
- Create: `README.md`

**Step 1: Write README.md**

```markdown
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
```

**Step 2: Commit**

```bash
git add README.md
git commit -m "feat: add README"
```

---

### Task 11: Add Spec and Plan Documents

**Files:**
- Verify: `spec/DESIGN.md` (already created)
- Verify: `docs/plans/2026-03-02-amun-docker.md` (this file)

**Step 1: Commit spec and plan**

```bash
git add spec/ docs/
git commit -m "docs: add design spec and implementation plan"
```

---

### Task 12: Final Validation

**Step 1: Run full syntax check**

Run:
```bash
cd /Users/galvarez/dev/amun-docker && ansible-playbook --syntax-check -i localhost main.yml
```
Expected: No errors.

**Step 2: Install ansible collections**

Run:
```bash
cd /Users/galvarez/dev/amun-docker && ansible-galaxy collection install -r requirements.yml
```
Expected: community.general and community.docker installed.

**Step 3: Verify git log**

Run:
```bash
cd /Users/galvarez/dev/amun-docker && git log --oneline
```
Expected: Clean commit history with all tasks committed.
