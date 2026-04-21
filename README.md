# Juno Airgap Installer

Packages K3s and Juno into a self-contained bundle for deployment on machines with no internet access. The bundle includes all container images, Helm charts, Git repositories, and an Ansible-based installer — everything needed to bring up a fully operational Juno cluster offline.

## Quick Start

```bash
# On build machine (internet required)
git clone https://github.com/juno-fx/Juno-Airgap-Bundler.git
cd Juno-Airgap-Bundler
make build

# Transfer to target
rsync -avz --progress bundles/genesis-*.tar.gz user@target:/opt/

# On target machine
cd /opt
tar -xzf genesis-*.tar.gz
cd genesis-*/
sudo ./install.sh \
  --genesis-host juno.example.com \
  --basic-auth-email admin@example.com \
  --basic-auth-password yourpassword \
  --titan-owner adminuser \
  --titan-uid 1000
```

## Build Machine Requirements

| Tool     | Version | Purpose                                          |
|----------|---------|--------------------------------------------------|
| Docker   | Latest  | Pull and save container images                   |
| Helm     | Latest  | Pull ingress-nginx Helm chart                    |
| Git      | Latest  | Clone deployment repositories                    |
| curl     | Latest  | Download K3s airgap images and Juno installer    |
| Internet | Outbound HTTPS | GitHub, Docker Hub, registry.k8s.io, ghcr.io, quay.io, nvcr.io |

## Target Machine Requirements

| Requirement | Detail                                                       |
|-------------|--------------------------------------------------------------|
| OS          | Ubuntu 22+, Debian 12/13, RHEL/Rocky 9/10, AlmaLinux 10 (x86_64) |
| Docker      | Latest (CE)                                                  |
| CPU         | 8 cores minimum                                              |
| RAM         | 16GB minimum                                                 |
| Disk        | 75GB minimum                                                 |
| Network     | No internet required                                         |
| Access      | sudo                                                         |

## Build the Bundle

```bash
git clone https://github.com/juno-fx/Juno-Airgap-Bundler.git
cd Juno-Airgap-Bundler

# 1. Configure versions (see Configuration section below)
# 2. Add/remove images (see Configuration section below)

make build
```

Output: `bundles/genesis-<GENESIS_VERSION>-orion-<ORION_VERSION>.tar.gz`

## Configuration

### Versions

Edit the top of `build-bundle.sh`:

```bash
GENESIS_VERSION="3.0.2"
ORION_VERSION="3.1.0"
```

### Images

Edit `images.txt` before building. One Docker image reference per line:

```
docker.io/myorg/myimage:v1.0
quay.io/myorg/otherapp:latest
# Lines starting with # are ignored
```

Each image is saved as a separate tar file in the `images/` directory of the bundle. K3s auto-imports all tars from this directory on startup.

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

## Transfer to Target

```bash
rsync -avz --progress bundles/genesis-*.tar.gz user@target:/opt/
```

## Install

```bash
cd /opt
tar -xzf genesis-*.tar.gz
cd genesis-*/
sudo ./install.sh \
  --genesis-host juno.example.com \
  --basic-auth-email admin@example.com \
  --basic-auth-password yourpassword \
  --titan-owner adminuser \
  --titan-uid 1000
```

The installer will:

1. Load Docker images for the Git server
2. Start the Git server via Docker Compose
3. Create `/etc/rancher/k3s/config.yaml` with `embedded-registry: true`
4. Copy `registries.yaml` to `/etc/rancher/k3s/`
5. Copy all image tars to the K3s auto-import directory
6. Run Ansible to install K3s and deploy Juno

## Post-Install Verification

```bash
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A
sudo k3s ctr images ls
```

## Troubleshooting

```bash
sudo ./debug.sh
```

Share the resulting `debug.log` with Juno support.

Quick checks:

```bash
sudo systemctl status k3s
cat /etc/rancher/k3s/config.yaml
cat /etc/rancher/k3s/registries.yaml
```

## Useful Resources

| Resource                                                                                                                                                          | Description                                                          |
|-------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------|
| [K3s Airgap Installation](https://docs.k3s.io/installation/airgap)                                                                                                | Official K3s docs for air-gapped installs                            |
| [K3s Image Auto-Loading](https://docs.k3s.io/installation/airgap?airgap-load-images=Manually+Deploy+Images#prepare-the-images-directory-and-airgap-image-tarball) | How K3s auto-imports image tars from the images directory on startup |
| [K3s Embedded Registry](https://docs.k3s.io/installation/registry-mirror)                                                                                         | How the K3s embedded registry mirror works                           |
| [TinyGit](https://github.com/Eroyi/tinygit)                                                                                                                       | Lightweight Git server used to serve Juno repositories               |
