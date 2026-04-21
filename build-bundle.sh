#!/usr/bin/env bash
# build-bundle.sh
#
# Builds a self-contained airgap bundle for installing Juno on an offline machine.
#
# The bundle includes:
#   - Docker service images (git server) saved as tars
#   - K3s airgap image tarball (system images for K3s embedded registry)
#   - Application images from images.txt saved as tars
#   - Bare git repositories (Genesis, Orion, Terra, Juno-Bootstrap)
#   - Helm charts (ingress-nginx)
#   - Ansible installer (juno-oneclick.tar.gz)
#   - Rendered install.sh and values.yaml with versions baked in
#
# Prerequisites: docker, helm, git, curl, internet access
# Output: bundles/genesis-<GENESIS_VERSION>-orion-<ORION_VERSION>.tar.gz
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Version of Genesis and Orion to bundle. These control:
#   - Which git tag is cloned for each deployment repo
#   - The version strings baked into install.sh and values.yaml at build time
GENESIS_VERSION="3.0.2"
ORION_VERSION="3.1.0"

BUNDLE_NAME="genesis-${GENESIS_VERSION}-orion-${ORION_VERSION}"
WORK_DIR="${SCRIPT_DIR}/${BUNDLE_NAME}"

IMAGES_FILE="images.txt"

# Docker images for the git server service. These are saved to docker/ in the
# bundle and loaded by install.sh before docker compose starts.
DOCKER_IMAGES=(
    "aliolozy/tinygit:latest"
    "nginx:alpine"
)

# K3s version to download airgap images for. Must match the version that
# Ansible will install on the target. The SHA256 checksum is verified against
# the official K3s release checksum file before bundling.
K3S_VERSION="v1.33.1+k3s1"

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Build an airgap bundle containing Docker images and Git repositories.

OPTIONS:
    --help                Show this help message

EXAMPLES:
    $(basename "$0")

FILES:
    images.txt            List of images to include in bundle (one per line)
                          Lines starting with # are comments
                          Empty lines are ignored
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
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
    shift
done

IMAGES_FILE_PATH="${SCRIPT_DIR}/${IMAGES_FILE}"
if [ ! -f "${IMAGES_FILE_PATH}" ]; then
    echo "ERROR: ${IMAGES_FILE} not found at ${IMAGES_FILE_PATH}"
    echo "Create a ${IMAGES_FILE} file with one image per line (empty lines and # comments are ignored)"
    exit 1
fi

# Parse images.txt into an array, stripping blank lines and comments.
# The trailing `|| [ -n "$line" ]` handles files that lack a final newline.
K3S_APP_IMAGES=()
while IFS= read -r line || [ -n "$line" ]; do
    line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -z "$line" ] || [[ "$line" == \#* ]]; then
        continue
    fi
    K3S_APP_IMAGES+=("$line")
done < "${IMAGES_FILE_PATH}"

echo "Building ${BUNDLE_NAME}..."

# Create the top-level bundle directory and all required subdirectories up front.
mkdir -p "${WORK_DIR}"/{docker,images,git-repos,helm-charts}

# clone_git: shallow bare clone of a repo at a specific branch/tag.
# Bare clones contain only git objects (no working tree) which is what we
# need for the git server to serve them via HTTP.
clone_git() {
    local repo="$1" branch="$2" dest="$3"
    echo "[repos] $(basename "$dest" .git) (${branch})"
    git clone --branch "$branch" --depth 1 --single-branch --bare "$repo" "$dest"
}

# save_image: docker pull then save to a tar file.
# The tar filename is derived from the image reference with ':' and '/'
# replaced by '-' so it is a safe flat filename (e.g. nginx:alpine → nginx-alpine.tar).
save_image() {
    local image="$1" dest_dir="$2"
    echo "  ${image}"
    docker pull "$image"
    docker save -o "${dest_dir}/$(echo "$image" | tr ':/' '-').tar" "$image"
}

echo "[images] docker service images"
for image in "${DOCKER_IMAGES[@]}"; do
    save_image "$image" "${WORK_DIR}/docker"
done

echo "[images] k3s airgap (${K3S_VERSION})"
# Download K3s airgap image tarball and verify its SHA256 checksum against the
# official release checksum file. This catches truncated downloads or tampering
# before the bundle is shipped to an air-gapped machine where re-downloading
# is not possible. The checksum file is removed after verification.
curl -sL "https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s-airgap-images-amd64.tar" \
    -o "${WORK_DIR}/images/k3s-airgap-images-amd64.tar"
curl -sL "https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/sha256sum-amd64.txt" \
    -o "${WORK_DIR}/images/sha256sum-amd64.txt"
EXPECTED_SHA=$(grep "k3s-airgap-images-amd64.tar$" "${WORK_DIR}/images/sha256sum-amd64.txt" | awk '{print $1}')
ACTUAL_SHA=$(sha256sum "${WORK_DIR}/images/k3s-airgap-images-amd64.tar" | awk '{print $1}')
if [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
    echo "ERROR: SHA256 mismatch for k3s-airgap-images-amd64.tar"
    echo "  expected: ${EXPECTED_SHA}"
    echo "  actual:   ${ACTUAL_SHA}"
    rm -rf "${WORK_DIR}"
    exit 1
fi
echo "[images] k3s airgap SHA256 verified"
rm -f "${WORK_DIR}/images/sha256sum-amd64.txt"

echo "[images] app images"
for image in "${K3S_APP_IMAGES[@]}"; do
    save_image "$image" "${WORK_DIR}/images"
done

if [ -f "${SCRIPT_DIR}/templates/registries.yaml.in" ]; then
    cp "${SCRIPT_DIR}/templates/registries.yaml.in" "${WORK_DIR}/registries.yaml"
else
    echo "ERROR: templates/registries.yaml.in not found"
    rm -rf "${WORK_DIR}"
    exit 1
fi

clone_git "https://github.com/juno-fx/Genesis-Deployment.git" "v${GENESIS_VERSION}" "${WORK_DIR}/git-repos/Genesis-Deployment.git"
clone_git "https://github.com/juno-fx/Orion-Deployment.git" "v${ORION_VERSION}" "${WORK_DIR}/git-repos/Orion-Deployment.git"
clone_git "https://github.com/juno-fx/Terra-Official-Plugins.git" "main" "${WORK_DIR}/git-repos/Terra-Official-Plugins.git"
clone_git "https://github.com/juno-fx/Juno-Bootstrap.git" "main" "${WORK_DIR}/git-repos/Juno-Bootstrap.git"

if [ -f "${SCRIPT_DIR}/docker-compose.yaml" ]; then
    cp "${SCRIPT_DIR}/docker-compose.yaml" "${WORK_DIR}/"
else
    echo "ERROR: docker-compose.yaml not found in ${SCRIPT_DIR}"
    rm -rf "${WORK_DIR}"
    exit 1
fi

# install.sh ships with __GENESIS_VERSION__ and __ORION_VERSION__ placeholders.
# sed substitutes the actual version values at build time so the installed
# script on the target machine does not require any version arguments.
if [ -f "${SCRIPT_DIR}/install.sh" ]; then
    sed "s/__GENESIS_VERSION__/${GENESIS_VERSION}/g; s/__ORION_VERSION__/${ORION_VERSION}/g" \
        "${SCRIPT_DIR}/install.sh" > "${WORK_DIR}/install.sh"
    chmod +x "${WORK_DIR}/install.sh"
else
    echo "ERROR: install.sh not found in ${SCRIPT_DIR}"
    rm -rf "${WORK_DIR}"
    exit 1
fi

if [ -f "${SCRIPT_DIR}/templates/generate-extra-vars.py.in" ]; then
    cp "${SCRIPT_DIR}/templates/generate-extra-vars.py.in" "${WORK_DIR}/generate-extra-vars.py"
    chmod +x "${WORK_DIR}/generate-extra-vars.py"
else
    echo "ERROR: templates/generate-extra-vars.py.in not found"
    rm -rf "${WORK_DIR}"
    exit 1
fi

# values.yaml also contains version placeholders substituted at build time.
if [ -f "${SCRIPT_DIR}/templates/values.yaml.in" ]; then
    sed "s/__GENESIS_VERSION__/${GENESIS_VERSION}/g; s/__ORION_VERSION__/${ORION_VERSION}/g" \
        "${SCRIPT_DIR}/templates/values.yaml.in" > "${WORK_DIR}/values.yaml"
else
    echo "ERROR: templates/values.yaml.in not found"
    rm -rf "${WORK_DIR}"
    exit 1
fi

# Pull the ingress-nginx Helm chart from the official repo and generate a
# local index.yaml so the git server can serve it as a Helm repository.
# INGRESS_NGINX_VERSION defaults to 4.12.1 if not set in the environment.
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm pull ingress-nginx/ingress-nginx \
    --version "${INGRESS_NGINX_VERSION:-4.12.1}" \
    -d "${WORK_DIR}/helm-charts/" \
    --untar=false
helm repo index "${WORK_DIR}/helm-charts/"

# Copy helper scripts (update_dns.sh, debug.sh) if they exist. These are
# optional — the install will succeed without them.
for script in update_dns.sh debug.sh; do
    if [ -f "${SCRIPT_DIR}/${script}" ]; then
        cp "${SCRIPT_DIR}/${script}" "${WORK_DIR}/"
        chmod +x "${WORK_DIR}/${script}"
    fi
done

# Fetch the latest juno-oneclick.tar.gz release from the K8s-Playbooks repo.
# This is the singularity container that wraps Ansible and performs the
# actual K3s install + Juno deployment on the target machine.
JUNO_ONECLICK_URL=$(curl -sL "https://api.github.com/repos/juno-fx/K8s-Playbooks/releases/latest" | \
    grep -o '"browser_download_url": *"[^"]*juno-oneclick\.tar\.gz"' | \
    cut -d '"' -f4)
curl -sL "${JUNO_ONECLICK_URL}" -o "${WORK_DIR}/juno-oneclick.tar.gz"

# Package the entire work directory into a single tar.gz archive, then remove
# the uncompressed directory to reclaim disk space.
echo "[bundle] packaging ${BUNDLE_NAME}.tar.gz"
cd "${SCRIPT_DIR}"
tar -czf "${BUNDLE_NAME}.tar.gz" "${BUNDLE_NAME}"
rm -rf "${WORK_DIR}"

ls -lh "${SCRIPT_DIR}/${BUNDLE_NAME}.tar.gz"
