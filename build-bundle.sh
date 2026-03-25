#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
BUNDLE_NAME="airgap-bundle-${TIMESTAMP}"
WORK_DIR="${SCRIPT_DIR}/${BUNDLE_NAME}"

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

echo "=== Airgap Bundle Builder ==="
echo "Timestamp: ${TIMESTAMP}"
echo "Work directory: ${WORK_DIR}"
echo ""

mkdir -p "${WORK_DIR}/docker"
mkdir -p "${WORK_DIR}/git-repos"

echo "=== Step 1: Pulling and saving Docker images ==="
for image in "${DOCKER_IMAGES[@]}"; do
    echo "Pulling ${image}..."
    docker pull "${image}"
    
    image_name=$(echo "${image}" | tr ':/' '-')
    echo "Saving ${image} to docker/${image_name}.tar..."
    docker save -o "${WORK_DIR}/docker/${image_name}.tar" "${image}"
done

echo "=== Step 2: Cloning Git repositories ==="
for repo in "${GIT_REPOS[@]}"; do
    repo_name=$(basename "${repo}" .git)
    echo "Cloning ${repo}..."
    git clone --depth 10 --bare "${repo}" "${WORK_DIR}/git-repos/${repo_name}.git"
    cd "${WORK_DIR}/git-repos/${repo_name}.git" && \
        git fetch --depth 10 origin '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*'
done

echo ""
echo "=== Step 3: Creating docker-compose.yaml ==="
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
echo "=== Step 4: Creating load.sh ==="
cat > "${WORK_DIR}/load.sh" << 'EOF'
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="${SCRIPT_DIR}/docker"
GIT_REPOS_DIR="${SCRIPT_DIR}/git-repos"

echo "=== Loading Docker images into local socket ==="
for tar_file in "${DOCKER_DIR}"/*.tar; do
    if [ -f "${tar_file}" ]; then
        echo "Loading $(basename "${tar_file}")..."
        docker load -i "${tar_file}"
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
echo "=== Airgap Bundle Ready ==="
echo ""
echo "Services running:"
echo "  - Git Server:           http://localhost:8080/"
echo "  - Docker Registry:     http://localhost:5000"
echo ""
echo "Git repositories available at http://localhost:8080/:"
ls -1 "${GIT_REPOS_DIR}" | sed 's/^/  - /'
echo ""
echo "To load Docker images into K8s cluster, use:"
echo "  docker load -i <image>.tar"
echo "  docker push localhost:5000/<image>:<tag>"
EOF

chmod +x "${WORK_DIR}/load.sh"

echo ""
echo "=== Step 5: Creating tar.gz archive ==="
cd "${SCRIPT_DIR}"
tar -czf "${BUNDLE_NAME}.tar.gz" "${BUNDLE_NAME}"

echo ""
echo "=== Cleanup ==="
rm -rf "${WORK_DIR}"

echo ""
echo "=== Done ==="
echo "Bundle created: ${BUNDLE_NAME}.tar.gz"
ls -lh "${SCRIPT_DIR}/${BUNDLE_NAME}.tar.gz"
