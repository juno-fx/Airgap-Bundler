#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Bundle version metadata
GENESIS_VERSION="3.0.2"
ORION_VERSION="3.1.0"

BUNDLE_NAME="genesis-${GENESIS_VERSION}-orion-${ORION_VERSION}"
WORK_DIR="${SCRIPT_DIR}/${BUNDLE_NAME}"
REGISTRY_URL="localhost:5000"

IMAGES_FILE="images.txt"

DOCKER_IMAGES=(
    "aliolozy/tinygit:latest"
    "registry:3"
)

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Build an airgap bundle containing Docker images and Git repositories.

OPTIONS:
    --registry-url URL    Docker registry URL (default: localhost:5000)
    --help                Show this help message

EXAMPLES:
    $(basename "$0")
    $(basename "$0") --registry-url myregistry:5000

FILES:
    images.txt            List of images to include in registry (one per line)
                          Lines starting with # are comments
                          Empty lines are ignored
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --registry-url)
            REGISTRY_URL="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

IMAGES_FILE_PATH="${SCRIPT_DIR}/${IMAGES_FILE}"
if [ ! -f "${IMAGES_FILE_PATH}" ]; then
    echo "ERROR: ${IMAGES_FILE} not found at ${IMAGES_FILE_PATH}"
    echo "Create a ${IMAGES_FILE} file with one image per line (empty lines and # comments are ignored)"
    exit 1
fi

REGISTRY_IMAGES=()
while IFS= read -r line || [ -n "$line" ]; do
    line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -z "$line" ] || [[ "$line" == \#* ]]; then
        continue
    fi
    REGISTRY_IMAGES+=("$line")
done < "${IMAGES_FILE_PATH}"

echo "=== Airgap Bundle Builder ==="
echo "Bundle: ${BUNDLE_NAME}"
echo "Registry URL: ${REGISTRY_URL}"
echo "Work directory: ${WORK_DIR}"
echo "Images file: ${IMAGES_FILE_PATH}"
echo "Registry images: ${#REGISTRY_IMAGES[@]}"
echo ""

mkdir -p "${WORK_DIR}/docker"
mkdir -p "${WORK_DIR}/registry-images"
mkdir -p "${WORK_DIR}/git-repos"

echo "=== Step 1: Pulling and saving Docker images ==="
for image in "${DOCKER_IMAGES[@]}"; do
    echo "Pulling ${image}..."
    docker pull "${image}"
    
    image_name=$(echo "${image}" | tr ':/' '-')
    echo "Saving ${image} to docker/${image_name}.tar..."
    docker save -o "${WORK_DIR}/docker/${image_name}.tar" "${image}"
done

echo "=== Step 2: Pulling and saving registry images ==="
for image in "${REGISTRY_IMAGES[@]}"; do
    echo "Pulling ${image}..."
    docker pull "${image}"
    
    image_name=$(echo "${image}" | tr ':/' '-')
    echo "Saving ${image} to registry-images/${image_name}.tar..."
    docker save -o "${WORK_DIR}/registry-images/${image_name}.tar" "${image}"
done

echo "=== Step 3: Cloning Git repositories ==="

echo "Cloning Genesis-Deployment (branch v${GENESIS_VERSION})..."
git clone --branch "v${GENESIS_VERSION}" --depth 10 --bare \
    "https://github.com/juno-fx/Genesis-Deployment.git" \
    "${WORK_DIR}/git-repos/Genesis-Deployment.git"
cd "${WORK_DIR}/git-repos/Genesis-Deployment.git" && \
    git fetch --depth 10 origin '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*'

echo "Cloning Orion-Deployment (branch v${ORION_VERSION})..."
git clone --branch "v${ORION_VERSION}" --depth 10 --bare \
    "https://github.com/juno-fx/Orion-Deployment.git" \
    "${WORK_DIR}/git-repos/Orion-Deployment.git"
cd "${WORK_DIR}/git-repos/Orion-Deployment.git" && \
    git fetch --depth 10 origin '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*'

echo "Cloning Terra-Official-Plugins (branch main)..."
git clone --branch main --depth 10 --bare \
    "https://github.com/juno-fx/Terra-Official-Plugins.git" \
    "${WORK_DIR}/git-repos/Terra-Official-Plugins.git"
cd "${WORK_DIR}/git-repos/Terra-Official-Plugins.git" && \
    git fetch --depth 10 origin '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*'

echo "Cloning ingress-nginx (branch main)..."
git clone --branch main --depth 10 --bare \
    "https://github.com/kubernetes/ingress-nginx.git" \
    "${WORK_DIR}/git-repos/ingress-nginx.git"
cd "${WORK_DIR}/git-repos/ingress-nginx.git" && \
    git fetch --depth 10 origin '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*'

echo ""
echo "=== Step 4: Creating docker-compose.yaml ==="
cat > "${WORK_DIR}/docker-compose.yaml" << 'EOF'
version: '3.8'

services:
  git:
    image: aliolozy/tinygit:latest
    container_name: git
    restart: unless-stopped
    ports:
      - "8080:80"
    volumes:
      - ./git-repos:/git
    environment:
      - AUTH_ENABLE=false

  registry:
    image: registry:3
    container_name: registry
    restart: unless-stopped
    ports:
      - "5000:5000"
    volumes:
      - registry-data:/var/lib/registry

volumes:
  registry-data:
EOF

echo ""
echo "=== Step 5: Creating load.sh ==="
cat > "${WORK_DIR}/load.sh" << 'LOADEOF'
#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="${SCRIPT_DIR}/docker"
REGISTRY_IMAGES_DIR="${SCRIPT_DIR}/registry-images"
GIT_REPOS_DIR="${SCRIPT_DIR}/git-repos"
REGISTRY_URL="localhost:5000"
PUSH_TO_REGISTRY=""
FAILED_PUSHES=()

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Load Docker images and start services for airgap bundle.

OPTIONS:
    --registry-url URL    Local registry URL (default: localhost:5000)
    --push-to URL         Also push images to remote registry URL
    --help                Show this help message

EXAMPLES:
    $(basename "$0")
    $(basename "$0") --push-to myregistry:5000
    $(basename "$0") --registry-url 5001:5000 --push-to remote:5000
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --registry-url)
            REGISTRY_URL="$2"
            shift 2
            ;;
        --push-to)
            PUSH_TO_REGISTRY="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

echo "=== Loading Docker images into local socket ==="
for tar_file in "${DOCKER_DIR}"/*.tar; do
    if [ -f "${tar_file}" ]; then
        echo "Loading $(basename "${tar_file}")..."
        docker load -i "${tar_file}"
    fi
done

load_and_push_registry_image() {
    local tar_file="$1"
    
    LOAD_OUTPUT=$(docker load -i "${tar_file}")
    echo "${LOAD_OUTPUT}"
    
    image_name_clean=$(echo "${LOAD_OUTPUT}" | sed 's/Loaded image: //')
    
    echo "Tagging for registry: ${REGISTRY_URL}/${image_name_clean}"
    docker tag "${image_name_clean}" "${REGISTRY_URL}/${image_name_clean}"
    
    echo "Pushing to registry: ${REGISTRY_URL}/${image_name_clean}"
    if ! docker push "${REGISTRY_URL}/${image_name_clean}"; then
        echo "WARNING: Failed to push ${image_name_clean} to local registry"
        FAILED_PUSHES+=("${image_name_clean}")
    fi
    
    if [ -n "${PUSH_TO_REGISTRY}" ]; then
        echo ""
        echo "=== Pushing to remote registry: ${PUSH_TO_REGISTRY} ==="
        echo "Tagging ${image_name_clean} for ${PUSH_TO_REGISTRY}"
        docker tag "${image_name_clean}" "${PUSH_TO_REGISTRY}/${image_name_clean}"
        
        echo "Pushing to ${PUSH_TO_REGISTRY}"
        if ! docker push "${PUSH_TO_REGISTRY}/${image_name_clean}"; then
            echo "WARNING: Failed to push ${image_name_clean} to remote registry"
            FAILED_PUSHES+=("${image_name_clean} (remote)")
        fi
    fi
}

echo ""
echo "=== Loading images into local registry ==="
for tar_file in "${REGISTRY_IMAGES_DIR}"/*.tar; do
    if [ -f "${tar_file}" ]; then
        echo "Loading $(basename "${tar_file}")..."
        load_and_push_registry_image "${tar_file}"
    fi
done

echo ""
echo "=== Starting Docker Compose stack ==="
docker compose up -d

echo "Waiting for git server to be ready..."
max_retries=30
retry_count=0
while ! curl -s http://localhost:8080/ > /dev/null 2>&1; do
    sleep 1
    retry_count=$((retry_count + 1))
    if [ ${retry_count} -ge ${max_retries} ]; then
        echo "ERROR: Git server failed to start after ${max_retries} seconds"
        exit 1
    fi
done
echo "Git server is ready"

echo ""
echo "=== Waiting for registry to be ready ==="
max_retries=30
retry_count=0
while ! curl -s "http://${REGISTRY_URL}/v2/" > /dev/null 2>&1; do
    sleep 1
    retry_count=$((retry_count + 1))
    if [ ${retry_count} -ge ${max_retries} ]; then
        echo "ERROR: Registry failed to start after ${max_retries} seconds"
        exit 1
fi
done

if [ ${#FAILED_PUSHES[@]} -gt 0 ]; then
    echo ""
    echo "=== Warning: Failed Pushes ==="
    echo "The following images failed to push:"
    for failed in "${FAILED_PUSHES[@]}"; do
        echo "  - ${failed}"
    done
    echo ""
fi

echo ""

echo ""
echo "=== Airgap Bundle Ready ==="
echo ""
echo "Services running:"
echo "  - Git Server:           http://localhost:8080/"
echo "  - Docker Registry:     http://${REGISTRY_URL}"
if [ -n "${PUSH_TO_REGISTRY}" ]; then
    echo "  - Remote Registry:    http://${PUSH_TO_REGISTRY}"
fi
echo ""
echo "Git repositories available at http://localhost:8080/:"
ls -1 "${GIT_REPOS_DIR}" | sed 's/^/  - /'
echo ""
echo "Registry images available at http://${REGISTRY_URL}:"
curl -s "http://${REGISTRY_URL}/v2/_catalog" | grep -o '"repositories":\[[^]]*\]' || echo "  (checking...)"
if [ -n "${PUSH_TO_REGISTRY}" ]; then
    echo ""
    echo "Registry images pushed to http://${PUSH_TO_REGISTRY}:"
    curl -s "http://${PUSH_TO_REGISTRY}/v2/_catalog" | grep -o '"repositories":\[[^]]*\]' || echo "  (checking...)"
fi

echo ""
echo "=== Run Orion Installer? ==="
echo "The Orion installer will launch an interactive wizard to configure your deployment."
read -p "Run Orion installer now? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ -f "./orion-install-helper" ]; then
        echo "Starting Orion installer..."
        ./orion-install-helper
    else
        echo "ERROR: orion-install-helper not found in current directory"
        exit 1
    fi
fi

echo ""
echo "To load Docker images into K8s cluster, use:"
echo "  docker load -i <image>.tar"
echo "  docker push localhost:5000/<image>:<tag>"
LOADEOF

chmod +x "${WORK_DIR}/load.sh"

echo ""
echo "=== Step 6: Copying helper scripts ==="
if [ -f "${SCRIPT_DIR}/update_dns.sh" ]; then
    cp "${SCRIPT_DIR}/update_dns.sh" "${WORK_DIR}/"
    chmod +x "${WORK_DIR}/update_dns.sh"
    echo "Copied update_dns.sh to bundle"
else
    echo "WARNING: update_dns.sh not found, skipping"
fi

echo ""
echo "=== Step 6b: Downloading Orion installer ==="
curl -sL "$(curl -s https://api.github.com/repos/juno-fx/Juno-Bootstrap/releases/latest | grep browser_download_url | grep orion-install-helper | cut -d '"' -f 4)" > "${WORK_DIR}/orion-install-helper"
chmod +x "${WORK_DIR}/orion-install-helper"
echo "Downloaded orion-install-helper"

echo ""
echo "=== Step 7: Creating tar.gz archive ==="
cd "${SCRIPT_DIR}"
tar -czf "${BUNDLE_NAME}.tar.gz" "${BUNDLE_NAME}"

echo ""
echo "=== Cleanup ==="
rm -rf "${WORK_DIR}"

echo ""
echo "=== Done ==="
echo "Bundle created: ${BUNDLE_NAME}.tar.gz"
ls -lh "${SCRIPT_DIR}/${BUNDLE_NAME}.tar.gz"