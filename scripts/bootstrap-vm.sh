#!/bin/bash
set -e

echo "=== Bootstrapping Airgapped VM ==="

echo "Updating package list..."
apt-get update -y

echo "Installing prerequisites..."
apt-get install -y ca-certificates curl gnupg lsb-release

echo "Adding Docker GPG key..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "Adding Docker repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "Installing Docker..."
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "Adding current user to docker group..."
usermod -aG docker vagrant

echo "Setting vagrant password..."
echo "vagrant:vagrant" | chpasswd

echo "Enabling password SSH..."
echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
systemctl restart sshd

echo "Starting Docker service..."
systemctl start docker
systemctl enable docker

echo "=== Docker installed successfully ==="
docker --version
docker compose version

echo ""
echo "=== Airgap Bundle Ready ==="
echo "Bundle tar.gz is at: /bundles/"
echo ""
echo "To extract and run:"
echo "  cd /bundles"
echo "  tar -xzf genesis-*.tar.gz"
echo "  cd genesis-*/"
echo "  ./load.sh --push-to <registry-ip>:5000"
echo ""
echo "The VM is now ready for airgapped operations."