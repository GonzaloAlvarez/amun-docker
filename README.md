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
