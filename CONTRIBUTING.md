# Contributing

Development and VM testing workflow for Juno-Airgap-Bundler.

## Requirements

| Tool       | Purpose                 |
|------------|-------------------------|
| VirtualBox | VM hypervisor           |
| Vagrant    | VM lifecycle management |
| Make       | Build and VM commands   |

## VM Testing Workflow

### 1. Build the bundle

```bash
make build
```

Output: `bundles/genesis-*.tar.gz`

### 2. Stand up the VM

```bash
make destroy   # Destroy any existing VM
make up        # Start VM (rsyncs bundle automatically)
```

### 3. Verify bundle is present

```bash
vagrant ssh -c "ls -la /bundles/"
```

### 4. SSH into VM

```bash
make ssh
```

### 5. Run the installer

```bash
cd /bundles
tar -xzf genesis-*.tar.gz
cd genesis-*/
sudo ./install.sh \
  --genesis-host juno.example.com \
  --basic-auth-email admin@example.com \
  --basic-auth-password yourpassword \
  --titan-owner adminuser \
  --titan-uid 1000
```

### 6. Verify the install

```bash
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A
sudo k3s ctr images ls
```

### 7. Tear down

```bash
make halt     # Stop VM (preserves state)
make destroy  # Destroy VM entirely
```

## VM Configuration

| Setting        | Value                             |
|----------------|-----------------------------------|
| Disk           | 75GB (LVM expanded on first boot) |
| Memory         | 16GB                              |
| CPUs           | 8                                 |
| Host I/O Cache | Enabled                           |
| Bundle sync    | rsync (`.tar.gz` only)            |

The bundle is extracted on the VM with `--skip-old-files` so subsequent `make up` runs are faster.

## Firewall

The VM blocks outbound internet via UFW to simulate a true airgap. Local and SSH traffic from the host is allowed.

```bash
sudo ufw status verbose   # Check status
sudo ufw disable          # Re-enable internet temporarily (debugging only)
```

Verify internet is blocked:
```bash
ping -c 1 8.8.8.8         # Should fail
curl -I https://google.com # Should fail
```

## Debugging

Run the debug script on the VM to capture full system state:

```bash
sudo ./debug.sh
```

This produces `debug.log` containing:
- K3s service status
- Config files (`/etc/rancher/k3s/`)
- K3s image directory contents
- Containerd images list
- Cluster and pod status
- K3s events

Additional manual checks:

```bash
sudo systemctl status k3s
cat /etc/rancher/k3s/config.yaml
cat /etc/rancher/k3s/registries.yaml
sudo k3s ctr images ls
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A
```

## Linting

```bash
make lint
```

Runs `shellcheck -e SC2001` against all shell scripts.
