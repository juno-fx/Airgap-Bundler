#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="${SCRIPT_DIR}/.test-integration"
BUNDLE_PATTERN="airgap-bundle*.tar.gz"
BUNDLE_DIR=""
IMAGES_FILE="images.txt"
IMAGES_FILE_BACKUP=""

cleanup() {
    local exit_code=$?
    echo ""
    echo "=== Cleaning up ==="
    
    if [ -n "${BUNDLE_DIR:-}" ] && [ -d "${BUNDLE_DIR}" ]; then
        cd "${BUNDLE_DIR}"
        if [ -f docker-compose.yaml ]; then
            docker compose down --volumes 2>/dev/null || true
        fi
    fi
    
    if [ -n "${IMAGES_FILE_BACKUP:-}" ] && [ -f "${IMAGES_FILE_BACKUP}" ]; then
        mv "${IMAGES_FILE_BACKUP}" "${SCRIPT_DIR}/${IMAGES_FILE}"
    fi
    
    rm -rf "${TEST_DIR}"
    rm -f "${BUNDLE_PATTERN}"
    
    echo "Cleanup complete (exit code: ${exit_code})"
    exit "${exit_code}"
}

trap cleanup EXIT

echo "=== Integration Test Suite ==="
echo ""

echo "=== Step 0: Setup test images.txt ==="
if [ -f "${SCRIPT_DIR}/${IMAGES_FILE}" ]; then
    IMAGES_FILE_BACKUP="${SCRIPT_DIR}/${IMAGES_FILE}.test-backup"
    mv "${SCRIPT_DIR}/${IMAGES_FILE}" "${IMAGES_FILE_BACKUP}"
fi

cat > "${SCRIPT_DIR}/${IMAGES_FILE}" << 'EOF'
alpine:latest
busybox:latest
EOF

echo "Created test images.txt with:"
cat "${SCRIPT_DIR}/${IMAGES_FILE}"
echo ""

echo "=== Step 1: Build the bundle ==="
./build-bundle.sh

BUNDLE_FILE=$(find . -maxdepth 1 -name "airgap-bundle*.tar.gz" -type f 2>/dev/null | head -n1)
if [ -z "${BUNDLE_FILE}" ]; then
    echo "ERROR: No bundle file created"
    exit 1
fi
echo "Bundle created: ${BUNDLE_FILE}"
echo ""

echo "=== Step 2: Extract bundle ==="
mkdir -p "${TEST_DIR}"
tar -xzf "${BUNDLE_FILE}" -C "${TEST_DIR}"

BUNDLE_DIR=$(find "${TEST_DIR}" -maxdepth 1 -name "airgap-bundle*" -type d 2>/dev/null | head -n1)
if [ -z "${BUNDLE_DIR}" ]; then
    echo "ERROR: Bundle extraction failed"
    exit 1
fi
cd "${BUNDLE_DIR}"
echo "Extracted to: ${BUNDLE_DIR}"
echo ""

echo "=== Step 2.1: Verify registry-images directory ==="
if [ -d "registry-images" ]; then
    REGISTRY_IMAGE_COUNT=$(find registry-images -maxdepth 1 -name "*.tar" | wc -l)
    echo "Registry images directory exists with ${REGISTRY_IMAGE_COUNT} tar files"
    ls -la registry-images/
else
    echo "ERROR: registry-images directory not found"
    exit 1
fi
echo ""

echo "=== Step 3: Start services (load.sh) ==="
./load.sh

echo "Waiting for services to be ready..."
sleep 5

echo "=== Step 4: Test Docker Registry ==="

TEST_IMAGE_NAME="test-image"
TEST_IMAGE_TAG="test-tag"
TEST_IMAGE_FULL="localhost:5000/${TEST_IMAGE_NAME}:${TEST_IMAGE_TAG}"

echo "Pulling alpine image for testing..."
docker pull alpine:latest

echo "Tagging for local registry..."
docker tag alpine:latest "${TEST_IMAGE_FULL}"

echo "Pushing to local registry..."
docker push "${TEST_IMAGE_FULL}"

echo "Removing local image..."
docker rmi "${TEST_IMAGE_FULL}" alpine:latest

echo "Pulling from local registry..."
docker pull "${TEST_IMAGE_FULL}"

if docker images "${TEST_IMAGE_FULL}" | grep -q "${TEST_IMAGE_TAG}"; then
    echo "Docker Registry: PASS"
else
    echo "Docker Registry: FAIL"
    exit 1
fi

echo ""

echo "=== Step 5: Test Registry Images ==="

echo "Checking registry catalog..."
REGISTRY_CATALOG=$(curl -s http://localhost:5000/v2/_catalog)
echo "Registry catalog: ${REGISTRY_CATALOG}"

if echo "${REGISTRY_CATALOG}" | grep -q "alpine"; then
    echo "Registry images (alpine): PASS"
else
    echo "Registry images (alpine): FAIL - alpine not found in registry"
    exit 1
fi

if echo "${REGISTRY_CATALOG}" | grep -q "busybox"; then
    echo "Registry images (busybox): PASS"
else
    echo "Registry images (busybox): FAIL - busybox not found in registry"
    exit 1
fi

echo ""

echo "=== Step 6: Test Git Server ==="

TEST_REPO_NAME="Orion-Deployment"
GIT_TEST_DIR="${TEST_DIR}/${TEST_REPO_NAME}"

echo "Cloning test repository from git server..."
rm -rf "${GIT_TEST_DIR}"
git clone "http://localhost:8080/git/${TEST_REPO_NAME}.git" "${GIT_TEST_DIR}"

if [ -d "${GIT_TEST_DIR}/.git" ]; then
    echo "Clone: PASS"
else
    echo "Clone: FAIL"
    exit 1
fi

echo "Checking branches..."
cd "${GIT_TEST_DIR}"
BRANCH_COUNT=$(git branch -a | wc -l)
if [ "${BRANCH_COUNT}" -lt 2 ]; then
    echo "Branches: FAIL (only found ${BRANCH_COUNT} branch)"
    exit 1
fi
echo "Branches: PASS (${BRANCH_COUNT} branches)"

echo "Testing branch switch..."
git checkout v1.0 2>/dev/null || git checkout origin/v1.0 -b v1.0 2>/dev/null || git checkout -b v1.0 origin/v1.0 2>/dev/null || true
if git rev-parse --verify HEAD > /dev/null 2>&1; then
    echo "Branch switch: PASS"
else
    echo "Branch switch: FAIL"
    exit 1
fi

echo "Checking commit history..."
COMMIT_COUNT=$(git log --oneline | wc -l)
if [ "${COMMIT_COUNT}" -gt 0 ]; then
    echo "Commit history: PASS (${COMMIT_COUNT} commits)"
else
    echo "Commit history: FAIL"
    exit 1
fi

echo ""

echo "=== All Tests Passed ==="