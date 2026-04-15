# Airgap-Bundler

Helper script for loading and distributing Juno Innovations setup to non-internet enabled machines.

## What It Does

Airgap-Bundler packages Docker images and Git repositories into a tar.gz archive that can be transferred to air-gapped (offline) machines. On the target machine, the included `load.sh` script restores the Docker images and starts the services via docker-compose.

### Features

- **Docker Images**: Pulls and saves Docker images as tar files
- **Git Repositories**: Clones repositories as bare repositories for serving via git server
- **Registry Images**: Load custom images from `images.txt` into the local Docker registry
- **Automated Setup**: Generates docker-compose.yaml and load.sh scripts
- **Portable Bundle**: Creates a single tar.gz archive for easy transfer

## Prerequisites

- Docker must be installed and running
- Git must be available
- Network access to pull the defined Docker images and clone repositories

## Quick Start

1. Build the bundle:
   ```bash
   # Build the bundle (uses default localhost:5000 for registry)
   ./build-bundle.sh

   # Or use make (outputs to bundles/)
   make build
   ```

This creates `genesis-<version>-orion-<version>.tar.gz` (e.g., `genesis-3.0.2-orion-3.1.0.tar.gz`) in the `bundles/` directory.

> **Note**: The bundle includes a preset `images.txt` with default registry images. See [Registry Images (images.txt)](#registry-images-images-txt) to customize.

The bundle also downloads the Orion installer which will be launched after images are loaded.

## Configuration


### Registry Images (images.txt)

The `images.txt` file contains preset images to include in the local Docker registry. Edit it to customize.

**Format:**
- One image per line in `image:tag` format
- Lines starting with `#` are comments
- Use grouped headers with `# === Section Name ===`

**Example images.txt:**
```bash
# === Juno Core (genesis 2.0.3 / orion 2.0.1) ===

docker.io/junoinnovations/genesis:v4.0.2
docker.io/junoinnovations/hubble:v5.1.0
# ... more images

# === NVIDIA GPU Operator v25.10.1 ===

nvcr.io/nvidia/gpu-operator:v25.10.1
# ... more images
```

### Git Repositories

Git repositories are cloned with pinned branches in `build-bundle.sh`. To change versions, edit `GENESIS_VERSION` and `ORION_VERSION` at the top of the script:

```bash
GENESIS_VERSION="2.0.3"
ORION_VERSION="2.0.1"
```

### Docker Service Images

Edit the `DOCKER_IMAGES` array in `build-bundle.sh`:

```bash
DOCKER_IMAGES=(
    "aliolozy/tinygit:latest"
    "registry:3"
)
```

## Bundle File Structure

When extracted, the bundle contains:

```
genesis-3.0.2-orion-3.1.0/
├── docker/                      # Service images (tinygit, registry)
│   ├── aliolozy-tinygit-latest.tar
│   └── registry-3.tar
├── registry-images/             # User-provided images for local registry
│   ├── genesis-v4.0.2.tar
│   ├── hubble-v5.1.0.tar
│   └── ... (other images)
├── git-repos/                   # Git repositories (bare)
│   ├── Orion-Deployment.git    # branch v2.0.1
│   ├── Genesis-Deployment.git # branch v2.0.3
│   ├── Terra-Official-Plugins.git
│   └── ingress-nginx.git
├── docker-compose.yaml
├── load.sh
├── update_dns.sh                # DNS update helper script
└── orion-install-helper         # Juno Orion installer (launched from load.sh)
```

## Usage on Target Machine

1. Extract the bundle:
   ```bash
   tar -xzf genesis-3.0.2-orion-3.1.0.tar.gz
   cd genesis-3.0.2-orion-3.1.0
   ```

2. Run the load script:
   ```bash
   # Default: load locally only
   ./load.sh

   # Push images to a remote registry
   ./load.sh --push-to myregistry:5000
   ```

3. Services will be available at:
   - Git Server: http://localhost:8080/
   - Docker Registry: http://localhost:5000

4. The installer will launch automatically after images are loaded:
   - After images are loaded into the registry (and pushed if --push-to was specified)
   - You will be prompted: `Run Orion installer now? [y/N]:`
   - Enter `y` to launch the interactive Orion installer wizard

## Updating DNS in ArgoCD Application

When moving the installation to a new environment, update the DNS hostname in the ArgoCD "genesis" Application using the included helper script:

```bash
./update_dns.sh my.new.host
```

The script will:
1. Detect if k3s is available and use `k3s kubectl` accordingly
2. Verify cluster connectivity (exits with debug steps if unreachable)
3. Verify Application 'genesis' exists in argocd namespace
4. Update the following values:
   - `repoURL` hostname in sources
   - `env.NEXTAUTH_URL` helm parameter  
   - `host:` value in helm values
5. Verify all values were updated correctly

Example:
```bash
./update_dns.sh new.juno-deployment.com
```

Debug if cluster unreachable:
```bash
kubectl config current-context    # Check current context
kubectl get nodes                 # Verify cluster connectivity
kubectl get pods -n argocd        # Verify ArgoCD is installed
```

## Transferring to Target Machine

### Using rsync

Rsync is ideal for transferring the bundle as it supports resuming and is efficient:

```bash
# Rsync the bundle to a remote target machine
rsync -avz --progress airgap-bundle.tar.gz user@target-machine:/path/to/destination/

# Or transfer the extracted directory
rsync -avz --progress airgap-bundle/ user@target-machine:/path/to/destination/
```

### Using SCP

```bash
scp airgap-bundle.tar.gz user@target-machine:/path/to/destination/
```

### Using USB Drive

```bash
# Copy to USB drive (assuming /mnt/usb is mounted)
cp airgap-bundle.tar.gz /mnt/usb/

# On target machine, mount USB and copy
cp /mnt/usb/airgap-bundle.tar.gz /path/to/destination/
```

## Working with Git Repositories

The git server serves repositories from the `/git/` path.

### Cloning a Repository

```bash
# Clone from the local git server
git clone http://localhost:8080/git/Orion-Deployment.git

# Clone to a specific directory
git clone http://localhost:8080/git/Orion-Deployment.git my-project
```

### Branch Support

All branches are included in the bundle (last 10 commits per branch). This allows ArgoCD to:
- Deploy from any branch
- Roll back to previous commits within the branch

### Switching Branches

```bash
cd my-project
git fetch --all
git checkout v1.0
```

## Working with Docker Registry

The local Docker registry allows you to push and pull images without internet access.

### Listing Images in Registry

```bash
# List available repositories
curl http://localhost:5000/v2/_catalog

# List tags for a specific image
curl http://localhost:5000/v2/<image-name>/tags/list
```

### Pulling an Image from Registry

```bash
# Pull from local registry (on any machine that can reach the registry)
docker pull localhost:5000/nginx:latest

# Pull with custom registry URL
docker pull myregistry:5000/nginx:latest
```

### Loading Images from Bundle

The bundle includes pre-saved Docker images in the `docker/` directory. These are automatically loaded when running `./load.sh`. To manually load a specific image:

```bash
docker load -i docker/aliolozy-tinygit-latest.tar
```

### Registry Images

Images listed in `images.txt` are automatically loaded into the registry when running `./load.sh`. They are stored in `registry-images/` directory and pushed to the registry on startup.

## Cleanup

Remove build artifacts:

```bash
make clean
```

## Testing

Run the integration test to verify the build, extraction, Docker registry, and git server:

```bash
# Using make
make test

# Or directly
./test-integration.sh
```

The integration test performs:
1. Builds the bundle (including registry images)
2. Extracts to a temporary directory
3. Starts services via load.sh
4. Tests Docker registry (push/pull an image)
5. Tests Git server (clones a repository, lists branches, switches branches)
6. Verifies registry images are pushed to registry
7. Cleans up all artifacts regardless of pass or fail

## Linting

Run shellcheck to validate the scripts:

```bash
make lint
```

## Airgapped VM Testing

This project includes a Vagrant configuration to test the bundle in an airgapped VM environment using VirtualBox.

### Prerequisites

- [Vagrant](https://www.vagrantup.com/downloads) installed
- VirtualBox installed
- VirtualBox kernel module loaded (`vboxdrv`)

### Quick Start

```bash
# 1. Build the bundle (outputs to bundles/)
make build

# 2. Start the VM (syncs bundles/ to /bundles)
make up

# 3. SSH into VM
make ssh

# 4. Extract and run in VM:
cd /bundles
tar -xzf genesis-*.tar.gz
cd genesis-*/
./load.sh --push-to <registry-ip>:5000
```

### Updating Bundle in Running VM

After rebuilding with `make build`:

```
make rsync
```

### VM Targets (Makefile)

```bash
make up        # Create and start VM (with bundle sync)
make rsync     # Re-sync bundles to VM
make ssh       # SSH into VM
make halt      # Stop VM
make destroy   # Destroy VM
make status    # Show VM status
make airgap    # Disable internet (disconnect NAT)
make online    # Re-enable internet (reconnect NAT)
```

### VM Configuration

- **OS**: Ubuntu 22.04 LTS (jammy)
- **IP**: 192.168.56.10 (host-only network)
- **Resources**: 2 CPUs, 4GB RAM, 80GB disk
- **Bundle location**: `/bundles/`
- **Docker**: Installed automatically via bootstrap script

### Troubleshooting

#### VirtualBox kernel module not loaded

```bash
# Check if module is loaded
lsmod | grep vboxdrv

# Load the module
sudo modprobe vboxdrv

# Or rebuild modules
sudo /sbin/vboxconfig
```

#### First-time VM setup

The first time you run `make up`, it will:
1. Download the Ubuntu 22.04 box (~400MB)
2. Create the VM with specified resources
3. Run bootstrap script to install Docker
4. Sync bundles to `/bundles/`

This may take several minutes.

#### Network issues

The VM uses host-only networking (192.168.56.0/24). Make sure:
- VirtualBox Host-Only Ethernet Adapter is enabled
- No firewall blocking the 192.168.56.x subnet