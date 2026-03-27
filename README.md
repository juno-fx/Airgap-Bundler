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

   # Or use make
   make build
   ```

This creates `airgap-bundle.tar.gz` in the current directory.

> **Note**: The bundle includes a preset `images.txt` with default registry images. See [Registry Images (images.txt)](#registry-images-images-txt) to customize.

## Configuration


### Registry Images (images.txt)

The `images.txt` file is included with preset images. Edit it to customize which images are included in the local Docker registry.

**Format:**
- One image per line in `image:tag` format
- Lines starting with `#` are comments
- Empty lines are ignored

**Example images.txt:**
```bash
# Example images.txt
nginx:latest
postgres:15
redis:7-alpine
```

### Git Repositories

Edit the `GIT_REPOS` array in `build-bundle.sh`:

```bash
GIT_REPOS=(
    "https://github.com/juno-fx/Orion-Deployment.git"
    "https://github.com/juno-fx/Genesis-Deployment.git"
)
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
airgap-bundle/
├── docker/                      # Service images (tinygit, registry)
│   ├── aliolozy-tinygit-latest.tar
│   └── registry-3.tar
├── registry-images/             # User-provided images for local registry
│   ├── nginx-latest.tar
│   ├── postgres-15.tar
│   └── redis-7-alpine.tar
├── git-repos/                   # Git repositories (bare)
│   ├── Orion-Deployment.git
│   ├── Genesis-Deployment.git
│   └── Terra-Official-Plugins.git
├── docker-compose.yaml
├── load.sh
└── update_dns.sh                # DNS update helper script
```

## Usage on Target Machine

1. Extract the bundle:
   ```bash
   tar -xzf airgap-bundle.tar.gz
   cd airgap-bundle
   ```

2. Run the load script:
   ```bash
   ./load.sh
   ```

3. Services will be available at:
   - Git Server: http://localhost:8080/
   - Docker Registry: http://localhost:5000

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
# Using make
make lint

# Or directly with devbox
devbox run -- shellcheck build-bundle.sh test-integration.sh
```