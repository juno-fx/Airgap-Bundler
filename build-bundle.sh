#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
BUNDLE_NAME="airgap-bundle"
WORK_DIR="${SCRIPT_DIR}/${BUNDLE_NAME}-${TIMESTAMP}"
REGISTRY_URL="localhost:5000"

IMAGES_FILE="images.txt"
GIT_REPOS=(
    "https://github.com/juno-fx/Orion-Deployment.git"
    "https://github.com/juno-fx/Genesis-Deployment.git"
    "https://github.com/juno-fx/Terra-Official-Plugins.git"
    "https://github.com/kubernetes/ingress-nginx.git"
)

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
echo "Timestamp: ${TIMESTAMP}"
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
    echo "Validating ${image}..."
    if ! docker manifest inspect "${image}" > /dev/null 2>&1; then
        echo "ERROR: Image ${image} not found or inaccessible"
        exit 1
    fi
    
    echo "Pulling ${image}..."
    docker pull "${image}"
    
    image_name=$(echo "${image}" | tr ':/' '-')
    echo "Saving ${image} to registry-images/${image_name}.tar..."
    docker save -o "${WORK_DIR}/registry-images/${image_name}.tar" "${image}"
done

echo "=== Step 3: Cloning Git repositories ==="
for repo in "${GIT_REPOS[@]}"; do
    repo_name=$(basename "${repo}" .git)
    echo "Cloning ${repo}..."
    git clone --depth 10 --bare "${repo}" "${WORK_DIR}/git-repos/${repo_name}.git"
    cd "${WORK_DIR}/git-repos/${repo_name}.git" && \
        git fetch --depth 10 origin '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*'
done

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
cat > "${WORK_DIR}/load.sh" << EOF
#!/bin/bash
set -e

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="\${SCRIPT_DIR}/docker"
REGISTRY_IMAGES_DIR="\${SCRIPT_DIR}/registry-images"
GIT_REPOS_DIR="\${SCRIPT_DIR}/git-repos"
REGISTRY_URL="${REGISTRY_URL}"

echo "=== Loading Docker images into local socket ==="
for tar_file in "\${DOCKER_DIR}"/*.tar; do
    if [ -f "\${tar_file}" ]; then
        echo "Loading \$(basename "\${tar_file}")..."
        docker load -i "\${tar_file}"
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
    retry_count=\$((retry_count + 1))
    if [ \${retry_count} -ge \${max_retries} ]; then
        echo "ERROR: Git server failed to start after \${max_retries} seconds"
        exit 1
    fi
done
echo "Git server is ready"

echo ""
echo "=== Loading images into local registry ==="
for tar_file in "\${REGISTRY_IMAGES_DIR}"/*.tar; do
    if [ -f "\${tar_file}" ]; then
        echo "Loading \$(basename "\${tar_file}")..."
        docker load -i "\${tar_file}"
        
        image_name=\$(basename "\${tar_file}" .tar)
        image_name_clean=\$(echo "\${image_name}" | tr '-' ':' | sed 's/_/\//')
        
        echo "Tagging for registry: \${REGISTRY_URL}/\${image_name_clean}"
        docker tag "\${image_name_clean}" "\${REGISTRY_URL}/\${image_name_clean}"
        
        echo "Pushing to registry: \${REGISTRY_URL}/\${image_name_clean}"
        if ! docker push "\${REGISTRY_URL}/\${image_name_clean}"; then
            echo "ERROR: Failed to push \${image_name_clean} to registry"
            exit 1
        fi
    fi
done

echo ""
echo "=== Airgap Bundle Ready ==="
echo ""
echo "Services running:"
echo "  - Git Server:           http://localhost:8080/"
echo "  - Docker Registry:     http://\${REGISTRY_URL}"
echo ""
echo "Git repositories available at http://localhost:8080/:"
ls -1 "\${GIT_REPOS_DIR}" | sed 's/^/  - /'
echo ""
echo "Registry images available at http://\${REGISTRY_URL}:"
curl -s "http://\${REGISTRY_URL}/v2/_catalog" | grep -o '"repositories":\[[^]]*\]' || echo "  (checking...)"
echo ""
echo "To load Docker images into K8s cluster, use:"
echo "  docker load -i <image>.tar"
echo "  docker push localhost:5000/<image>:<tag>"
EOF

chmod +x "${WORK_DIR}/load.sh"

echo ""
echo "=== Step 6: Creating tar.gz archive ==="
cd "${SCRIPT_DIR}"
tar -czf "airgap-bundle.tar.gz" "${BUNDLE_NAME}-${TIMESTAMP}"

echo ""
echo "=== Cleanup ==="
rm -rf "${WORK_DIR}"

echo ""
echo "=== Done ==="
echo "Bundle created: airgap-bundle.tar.gz"
ls -lh "${SCRIPT_DIR}/airgap-bundle.tar.gz"