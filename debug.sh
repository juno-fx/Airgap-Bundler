#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="${SCRIPT_DIR}/debug.log"

exec > >(tee -a "${OUTPUT_FILE}") 2>&1

echo "=== K3s Airgap Debug Info ==="
echo "Generated: $(date)"
echo ""

echo "=== K3s Service Status ==="
sudo systemctl status k3s || true
echo ""

echo "=== K3s Service Failed Units (if any) ==="
sudo systemctl list-units --failed --type=service | grep k3s || echo "No failed k3s units"
echo ""

echo "=== K3s Config Files ==="
echo "=== /etc/rancher/k3s/k3s.yaml (server URL only — cert/key material redacted) ==="
sudo grep -E "^\s*(server|cluster):" /etc/rancher/k3s/k3s.yaml 2>/dev/null || echo "File not found"
echo ""

echo "=== /etc/rancher/k3s/config.yaml ==="
sudo cat /etc/rancher/k3s/config.yaml 2>/dev/null || echo "File not found"
echo ""

echo "=== /etc/rancher/k3s/registries.yaml ==="
sudo cat /etc/rancher/k3s/registries.yaml 2>/dev/null || echo "File not found"
echo ""

echo "=== K3s Binary ==="
which k3s || echo "k3s not in PATH"
k3s --version 2>/dev/null || echo "k3s version check failed"
echo ""

echo "=== K3s Install Script ==="
ls -la /opt/k3s/ 2>/dev/null || echo "/opt/k3s not found"
echo ""

echo "=== K3s Image Directory ==="
ls -la /var/lib/rancher/k3s/agent/images/ 2>/dev/null || echo "Image dir not found"
echo ""

echo "=== K3s Logs (last 50 lines) ==="
sudo journalctl -u k3s --no-pager -n 50 2>/dev/null || echo "No k3s journal logs"
echo ""

echo "=== K3s Install Script Output (if exists) ==="
sudo cat /var/log/k3s.log 2>/dev/null | tail -50 || echo "No k3s.log found"
echo ""

echo "=== Docker Status ==="
sudo systemctl status docker 2>/dev/null || true
echo ""

echo "=== Docker Containers Running ==="
docker ps -a 2>/dev/null || echo "Docker not available"
echo ""

echo "=== K3s Cluster Status ==="
sudo k3s kubectl get nodes -o wide 2>/dev/null || echo "K3s not ready"
echo ""

echo "=== K3s Pods (all namespaces) ==="
sudo k3s kubectl get pods -A -o wide 2>/dev/null || echo "K3s not ready"
echo ""

echo "=== K3s Pods with issues ==="
sudo k3s kubectl get pods -A 2>/dev/null | grep -E "Pending|ContainerCreating|Error|Failed|Evicted" || echo "No issues found"
echo ""

echo "=== ArgoCD Pods ==="
sudo k3s kubectl get pods -n argocd -o wide 2>/dev/null || echo "ArgoCD namespace not ready"
echo ""

echo "=== Describe stuck pod (if any) ==="
STUCK_POD=$(sudo k3s kubectl get pods -A 2>/dev/null | grep -E "Pending|ContainerCreating" | head -1 | awk '{print $2}')
STUCK_NS=$(sudo k3s kubectl get pods -A 2>/dev/null | grep -E "Pending|ContainerCreating" | head -1 | awk '{print $1}')
if [ -n "$STUCK_POD" ] && [ -n "$STUCK_NS" ]; then
    echo "Describing pod: $STUCK_POD in namespace: $STUCK_NS"
    sudo k3s kubectl describe pod "$STUCK_POD" -n "$STUCK_NS" 2>/dev/null | tail -40
fi
echo ""

echo "=== K3s Events (last 50) ==="
sudo k3s kubectl get events -A --sort-by='.lastTimestamp' 2>/dev/null | tail -50 || echo "K3s not ready"
echo ""

echo "=== K3s Events ( Errors Only ) ==="
sudo k3s kubectl get events -A --field-selector type=Warning 2>/dev/null | tail -30 || echo "No warning events"
echo ""

echo "=== Containerd Images ==="
sudo k3s ctr images ls 2>/dev/null | head -30 || echo "K3s not ready"
echo ""

echo "=== K3s Component Status ==="
sudo k3s kubectl get componentstatuses 2>/dev/null || echo "K3s not ready"
echo ""

echo "=== ArgoCD Application Status ==="
sudo k3s kubectl get applications -n argocd 2>/dev/null || echo "ArgoCD not ready"
echo ""

echo "=== ArgoCD Application Details (if exists) ==="
sudo k3s kubectl get applications -n argocd -o yaml 2>/dev/null | head -50 || echo "ArgoCD not ready"
echo ""

echo "=== Network Routes ==="
ip route show 2>/dev/null || echo "ip route not available"
echo ""

echo "=== Network Interfaces ==="
ip addr show 2>/dev/null || echo "ip addr not available"
echo ""

echo "=== System Info ==="
uname -a
free -h
df -h
echo ""

echo "=== Debug Complete ==="
echo "Output saved to: ${OUTPUT_FILE}"