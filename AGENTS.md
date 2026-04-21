# AGENTS.md - Airgap-Bundler

Guidelines for agents working in this repository.

## Project Overview

Airgap-Bundler packages K3s cluster components for installation on air-gapped (offline) machines. It uses K3s's embedded registry instead of a separate Docker registry container.

## Architecture

- **No separate registry container** — Uses K3s embedded registry
- **Images packaged as tar files in `images/` directory** — one tar per image
  - `k3s-airgap-images-amd64.tar` — K3s system images (pause, coredns, metrics-server, etc.)
  - `*.tar` — Application images from `images.txt`
- **Helm charts** packaged in `helm-charts/` directory
- **Git server only** via docker-compose (no registry service)
- **Registries configured** with localhost endpoints for embedded registry

## Key Files

| File                  | Purpose                                                                     |
|-----------------------|-----------------------------------------------------------------------------|
| `build-bundle.sh`     | Builds the bundle (downloads images, creates tars)                          |
| `install.sh`          | Target machine installer                                                    |
| `docker-compose.yaml` | Git server only (no registry)                                               |
| `images.txt`          | Application images to include (one per line, Docker image reference format) |
| `values.yaml`         | Ansible values with registry mirrors                                        |
| `debug.sh`            | Debug script for troubleshooting                                            |

## Build Machine Requirements

| Tool     | Version        | Purpose                                                        |
|----------|----------------|----------------------------------------------------------------|
| Docker   | Latest         | Pull and save container images                                 |
| Helm     | Latest         | Pull ingress-nginx Helm chart                                  |
| Git      | Latest         | Clone deployment repositories                                  |
| curl     | Latest         | Download K3s airgap images and Juno installer                  |
| Internet | Outbound HTTPS | GitHub, Docker Hub, registry.k8s.io, ghcr.io, quay.io, nvcr.io |

**Note:** Python is not required on the build machine.

## Target Machine Requirements

| Requirement | Detail                                                           |
|-------------|------------------------------------------------------------------|
| OS          | Ubuntu 22+, Debian 12/13, RHEL/Rocky 9/10, AlmaLinux 10 (x86_64) |
| Docker      | Latest (CE)                                                      |
| CPU         | 8 cores minimum                                                  |
| RAM         | 16GB minimum                                                     |
| Disk        | 75GB minimum                                                     |
| Network     | No internet required                                             |
| Access      | sudo                                                             |

## Build Process

1. Pull Docker service images (tinygit) → save as tar in `docker/`
2. Download k3s-airgap-images-amd64.tar from K3s releases
3. Pull application images from `images.txt` → save one tar per image in `images/`
4. Pull ingress-nginx Helm chart → save in `helm-charts/`
5. Generate registries.yaml (with embedded registry endpoints)
6. Clone Git repos (bare): Genesis-Deployment, Orion-Deployment, Terra-Official-Plugins, ingress-nginx, Juno-Bootstrap
7. Copy docker-compose.yaml, install.sh, values.yaml
8. Download juno-oneclick.tar.gz (singularity with ansible)
9. Create tar.gz archive → output to `bundles/`

## Build Commands

```bash
make build    # Outputs to bundles/
./build-bundle.sh
```

## Configuration

### Versions

Edit top of `build-bundle.sh`:
```bash
GENESIS_VERSION="3.0.2"
ORION_VERSION="3.1.0"
```

### Images

Edit `images.txt` — one Docker image reference per line. Lines starting with `#` are ignored. Each image becomes a separate tar file in the bundle's `images/` directory.

### Key Variables in build-bundle.sh

- `GENESIS_VERSION` — Genesis deployment version
- `ORION_VERSION` — Orion deployment version
- `DOCKER_IMAGES` — Service images to include (tinygit)
- `K3S_VERSION` — K3s version for airgap images
- `INGRESS_NGINX_VERSION` — ingress-nginx Helm chart version

## Install Process (install.sh)

| Step | Action                                                               |
|------|----------------------------------------------------------------------|
| 1    | Load Docker images (git server)                                      |
| 2    | Start Git server: `docker compose up -d`                             |
| 3    | Create `/etc/rancher/k3s/config.yaml` with `embedded-registry: true` |
| 4    | Copy `registries.yaml` to `/etc/rancher/k3s/`                        |
| 5    | Copy all image tars from `images/` to K3s auto-import dir            |
| 6    | Run Ansible (K3s install + Juno deployment via ArgoCD)               |

**Critical:** `/etc/rancher/k3s/config.yaml` must be created BEFORE K3s is installed (Ansible runs). The installer handles this automatically — do not reorder steps.

**Note:** There is no internet connectivity check. UFW blocks internet access on the target VM during testing.

## Bundle Contents

```
genesis-3.0.2-orion-3.1.0/
├── images/                         # Container image tar files
│   ├── k3s-airgap-images-amd64.tar # K3s system images
│   └── *.tar                       # One tar per image in images.txt
├── helm-charts/                    # Helm chart packages
├── git-repos/                      # Bare git repositories
│   ├── Genesis-Deployment.git
│   ├── Orion-Deployment.git
│   ├── Terra-Official-Plugins.git
│   └── Juno-Bootstrap.git
├── docker/                         # Docker service image tars
│   └── *.tar                       # Git server image
├── registries.yaml                 # K3s embedded registry config
├── docker-compose.yaml             # Git server
├── install.sh                      # Main installer
├── values.yaml                     # Ansible values
├── juno-oneclick.tar.gz            # Singularity container with Ansible
└── debug.sh                        # Debug script
```

## Known Issues and Solutions

### Embedded Registry Not Working

**Symptom:** K3s tries to pull from docker.io instead of using embedded registry

**Solution:** Ensure `config.yaml` is created BEFORE K3s is installed:
```bash
mkdir -p /etc/rancher/k3s
echo "embedded-registry: true" | sudo tee /etc/rancher/k3s/config.yaml
# Then run ansible
```

## Debugging

Run `./debug.sh` on target machine to capture:
- K3s service status
- Config files (`/etc/rancher/k3s/`)
- K3s image directory contents
- Containerd images list
- K3s cluster/pod status
- K3s events

## Linting

```bash
make lint
shellcheck -e SC2001 build-bundle.sh install.sh update_dns.sh debug.sh
```

## Shell Script Conventions

- Use `set -euo pipefail`
- UPPERCASE for constants: `BUNDLE_NAME`, `WORK_DIR`
- Quote variables: `"${VAR}"`
- Use `[[ ]]` for tests
- Functions: `function_name() { ... }`
- Local vars: `local var=value`
- Arrays: `local -a ARRAY=("item1" "item2")`
- **Do not use empty `echo ""` commands** — they have been removed and should not be re-introduced

## VM Testing

VM testing workflow is documented in `CONTRIBUTING.md`.

## Agent Workflow for VM Testing

| Step | Command                             | Description                 |
|------|-------------------------------------|-----------------------------|
| 1    | `make build`                        | Build bundle to `bundles/`  |
| 2    | `make destroy`                      | Destroy old VM (if exists)  |
| 3    | `make up`                           | Stand up VM (rsyncs bundle) |
| 4    | `vagrant ssh -c "ls -la /bundles/"` | Verify bundle extracted     |

After step 4, notify user: ready for testing.

### Debug Access

When user calls agent in for debugging:
```bash
make ssh
sudo k3s ctr images ls
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A
cat /etc/rancher/k3s/config.yaml
./debug.sh
```

### Verify Internet Blocked

```bash
# Inside VM (as root)
ping -c 1 8.8.8.8       # Should fail
curl -I https://google.com  # Should fail
```

### Re-enable Internet (debugging only)

```bash
sudo ufw disable
```

### Post-Install Verification

```bash
sudo k3s check-config
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A
sudo k3s ctr images ls
```

## VM Configuration

| Setting        | Value | Description                       |
|----------------|-------|-----------------------------------|
| Disk           | 75GB  | Expanded LVM on first boot        |
| Memory         | 16GB  | RAM allocation                    |
| CPUs           | 8     | vCPU allocation                   |
| Host I/O Cache | On    | Better disk performance           |
| Sync Method    | rsync | Only `.tar.gz` files synced on up |

Bundles are synced via rsync on `vagrant up`. The archive is extracted locally with `--skip-old-files` for faster subsequent runs.

## Firewall Configuration (VM)

UFW is configured to:
- **Block** outgoing internet connections
- **Allow** SSH from host (192.168.56.0/24)
- **Allow** local network traffic (10.0.0.0/8)

```bash
sudo ufw status verbose   # Check status
sudo ufw disable          # Re-enable internet temporarily
```

## K3s Embedded Registry

Enabled via `/etc/rancher/k3s/config.yaml`:
```yaml
embedded-registry: true
```

When enabled:
- K3s serves images from local storage
- Images in `/var/lib/rancher/k3s/agent/images/` are auto-imported on startup
- No internet required for image pulls

## References

- [K3s Airgap Installation](https://docs.k3s.io/installation/airgap)
- [K3s Registry Mirror](https://docs.k3s.io/installation/registry-mirror)
- [juno_k3s Ansible Role](https://github.com/juno-fx/juno_k3s)
- [K8s-Playbooks](https://github.com/juno-fx/K8s-Playbooks)
- [Juno-Bootstrap](https://github.com/juno-fx/Juno-Bootstrap)
