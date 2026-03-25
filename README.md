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

1. Create an `images.txt` file with the images you want to include in the registry:
   ```bash
   # Create images.txt with your desired images
   cat > images.txt << 'EOF'
   nginx:latest
   postgres:15
   redis:7-alpine
   EOF
   ```

2. Build the bundle:
   ```bash
   # Build the bundle (uses default localhost:5000 for registry)
   ./build-bundle.sh

   # Or use make
   make build
   ```

This creates `airgap-bundle.tar.gz` in the current directory.

> **Note**: The `images.txt` file is required. See [Registry Images (images.txt)](#registry-images-images-txt) for more details.

## Configuration

### CLI Options

```bash
./build-bundle.sh --registry-url <url>
```

| Option | Description | Default |
|--------|-------------|---------|
| `--registry-url` | Docker registry URL | `localhost:5000` |
| `--help` | Show help message | - |

Example:
```bash
./build-bundle.sh --registry-url myregistry:5000
```

### Registry Images (images.txt)

Create an `images.txt` file in the same directory as `build-bundle.sh` to include custom images in the local Docker registry.

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

See `images.txt.example` for more examples.

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
└── load.sh
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