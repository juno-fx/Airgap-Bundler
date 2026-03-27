#!/bin/bash
set -euo pipefail

TEMP_FILE=""
cleanup() {
    if [[ -n "${TEMP_FILE}" ]] && [[ -f "${TEMP_FILE}" ]]; then
        rm -f "${TEMP_FILE}"
    fi
}
trap cleanup EXIT

if command -v k3s &>/dev/null; then
    KUBECTL_CMD="k3s kubectl"
else
    KUBECTL_CMD="kubectl"
fi

show_help() {
    cat << EOF
Usage: $(basename "$0") <new-dns-host>

Update DNS hostname in ArgoCD Application 'genesis'.

Arguments:
    new-dns-host    The new DNS hostname (e.g., my.new.host)

Example:
    $(basename "$0") new.juno-deployment.com

The script updates:
  - repoURL hostname in sources (preserves port)
  - env.NEXTAUTH_URL helm parameter
  - host value in helm values

Prerequisites:
  - kubectl configured with access to cluster running ArgoCD
  - Application 'genesis' exists in argocd namespace
EOF
}

if [[ $# -eq 0 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    show_help
    exit 0
fi

if [[ $# -ne 1 ]]; then
    echo "ERROR: Invalid number of arguments"
    echo ""
    show_help
    exit 1
fi

NEW_HOST="$1"

echo "=== Preflight Check ==="
echo "Using kubectl command: ${KUBECTL_CMD}"

if ! ${KUBECTL_CMD} cluster-info &>/dev/null; then
    echo "ERROR: Cannot reach Kubernetes cluster"
    echo ""
    echo "Debug steps:"
    echo "1. Verify kubectl is configured: ${KUBECTL_CMD} config current-context"
    echo "2. Check cluster connectivity: ${KUBECTL_CMD} get nodes"
    echo "3. For k3s: Ensure k3s service is running (sudo systemctl status k3s)"
    echo "4. Check kubeconfig file: ~/.kube/config exists and is valid"
    echo "5. Verify ArgoCD is installed: ${KUBECTL_CMD} get pods -n argocd"
    exit 1
fi
echo "Cluster connectivity: OK"

if ! ${KUBECTL_CMD} get application genesis -n argocd &>/dev/null; then
    echo "ERROR: Application 'genesis' not found in argocd namespace"
    echo "Run: ${KUBECTL_CMD} get applications -n argocd"
    exit 1
fi
echo "Application 'genesis': Found"
echo ""

echo "=== Current Values ==="
CURRENT_REPO_URL=$(${KUBECTL_CMD} get application genesis -n argocd -o jsonpath='{.spec.sources[0].repoURL}')
CURRENT_NEXTAUTH=$(${KUBECTL_CMD} get application genesis -n argocd -o jsonpath='{.spec.sources[0].helm.parameters[?(@.name=="env.NEXTAUTH_URL")].value}')
CURRENT_VALUES=$(${KUBECTL_CMD} get application genesis -n argocd -o jsonpath='{.spec.sources[0].helm.values}')
CURRENT_HOST=$(echo "${CURRENT_VALUES}" | grep -oP '^\s*host:\s*\K.+' | tr -d ' ' || true)

echo "Current repoURL:       ${CURRENT_REPO_URL}"
echo "Current NEXTAUTH_URL: ${CURRENT_NEXTAUTH}"
echo "Current host:         ${CURRENT_HOST}"
echo ""

NEW_REPO_URL=$(echo "${CURRENT_REPO_URL}" | sed "s|://[^/:]*|://${NEW_HOST}|")
NEW_NEXTAUTH_URL="https://${NEW_HOST}/api/auth"

echo "=== New Values ==="
echo "New repoURL:       ${NEW_REPO_URL}"
echo "New NEXTAUTH_URL: ${NEW_NEXTAUTH_URL}"
echo "New host:         ${NEW_HOST}"
echo ""

echo "=== Applying Updates ==="

${KUBECTL_CMD} patch application genesis -n argocd \
    --type json \
    --patch "[{\"op\": \"replace\", \"path\": \"/spec/sources/0/repoURL\", \"value\": \"${NEW_REPO_URL}\"}]"

${KUBECTL_CMD} patch application genesis -n argocd \
    --type json \
    --patch "[{\"op\": \"replace\", \"path\": \"/spec/sources/0/helm/parameters/0/value\", \"value\": \"${NEW_NEXTAUTH_URL}\"}]"

TEMP_FILE=$(mktemp)
max_retries=3
retry_count=0
while [[ ${retry_count} -lt ${max_retries} ]]; do
    ${KUBECTL_CMD} get application genesis -n argocd -o yaml > "${TEMP_FILE}"
    sed -i "s|^[[:space:]]*host:.*|host: ${NEW_HOST}|" "${TEMP_FILE}"
    if ${KUBECTL_CMD} apply -f "${TEMP_FILE}" --server-side --field-manager kubectl --force-conflicts 2>/dev/null; then
        break
    fi
    retry_count=$((retry_count + 1))
    if [[ ${retry_count} -lt ${max_retries} ]]; then
        echo "Retry ${retry_count}/${max_retries} due to concurrent modification..."
        sleep 1
    fi
done
rm -f "${TEMP_FILE}"
TEMP_FILE=""

echo "Updates applied successfully"
echo ""

echo "=== Verification ==="
UPDATED_REPO_URL=$(${KUBECTL_CMD} get application genesis -n argocd -o jsonpath='{.spec.sources[0].repoURL}')
UPDATED_NEXTAUTH=$(${KUBECTL_CMD} get application genesis -n argocd -o jsonpath='{.spec.sources[0].helm.parameters[?(@.name=="env.NEXTAUTH_URL")].value}')
UPDATED_VALUES=$(${KUBECTL_CMD} get application genesis -n argocd -o jsonpath='{.spec.sources[0].helm.values}')
UPDATED_HOST=$(echo "${UPDATED_VALUES}" | grep -oP '^\s*host:\s*\K.+' | tr -d ' ' || true)

echo "Updated repoURL:       ${UPDATED_REPO_URL}"
echo "Updated NEXTAUTH_URL: ${UPDATED_NEXTAUTH}"
echo "Updated host:         ${UPDATED_HOST}"

if [[ "${UPDATED_REPO_URL}" == "${NEW_REPO_URL}" ]] && \
   [[ "${UPDATED_NEXTAUTH}" == "${NEW_NEXTAUTH_URL}" ]] && \
   [[ "${UPDATED_HOST}" == "${NEW_HOST}" ]]; then
    echo ""
    echo "SUCCESS: All values updated correctly"
else
    echo ""
    echo "WARNING: Some values may not have updated as expected"
    exit 1
fi