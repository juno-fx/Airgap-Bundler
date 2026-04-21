#!/usr/bin/env bash
# install.sh
#
# Installs Juno on an air-gapped machine from a pre-built bundle.
#
# High-level steps:
#   1. Collect required configuration (interactively or via CLI flags)
#   2. Load Docker service images and start the git server
#   3. Write K3s config (/etc/rancher/k3s/config.yaml) BEFORE Ansible runs K3s
#   4. Copy image tars to the K3s auto-import directory
#   5. Run Ansible (juno-oneclick) to install K3s and deploy Juno via ArgoCD
#
# NOTE: __GENESIS_VERSION__ and __ORION_VERSION__ are placeholders substituted
# by build-bundle.sh at bundle build time via sed. Do not hardcode values here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/install.log"

# juno-oneclick.tar.gz is the singularity container that wraps Ansible.
# values.yaml is the Ansible values file with versions baked in by build-bundle.sh.
ONECLICK_ARCHIVE="juno-oneclick.tar.gz"
VALUES_FILE="values.yaml"

# CLI options — all default to empty/zero so _prompt() will ask interactively
# when --non-interactive is not set.
PUBLIC_IP=""
GENESIS_HOST=""
BASIC_AUTH_EMAIL=""
BASIC_AUTH_PASSWORD=""
BASIC_AUTH_PASSWORD_FILE=""
TITAN_OWNER="juno"
TITAN_UID="1001"
NON_INTERACTIVE=0

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Install airgap bundle with K3s and Juno.

OPTIONS:
    --public-ip IP                 Public IP for git server (defaults to eth1 detection)
    --genesis-host HOST            Genesis FQDN (required)
    --basic-auth-email EMAIL       Basic auth email
    --basic-auth-password PASSWORD Basic auth password (or use --basic-auth-password-file)
    --basic-auth-password-file     Read basic auth password from file (safer for automation)
    --titan-owner OWNER            Titan owner username
    --titan-uid UID                Titan owner uid (numeric)
    --non-interactive              Do not prompt; fail if required values missing
    --help                         Show this help message

EXAMPLES:
    $(basename "$0") --genesis-host genesis.example.org --basic-auth-email admin@example.org
    $(basename "$0") --genesis-host genesis.example.org --basic-auth-email admin@example.org --basic-auth-password-file /tmp/pw
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --public-ip)
            PUBLIC_IP="$2"
            shift 2
            ;;
        --genesis-host)
            GENESIS_HOST="$2"
            shift 2
            ;;
        --basic-auth-email)
            BASIC_AUTH_EMAIL="$2"
            shift 2
            ;;
        --basic-auth-password)
            BASIC_AUTH_PASSWORD="$2"
            shift 2
            ;;
        --basic-auth-password-file)
            BASIC_AUTH_PASSWORD_FILE="$2"
            shift 2
            ;;
        --titan-owner)
            TITAN_OWNER="$2"
            shift 2
            ;;
        --titan-uid)
            TITAN_UID="$2"
            shift 2
            ;;
        --non-interactive)
            NON_INTERACTIVE=1
            shift
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

if [ -n "$PUBLIC_IP" ]; then
    GIT_SERVER_IP="$PUBLIC_IP"
else
    # Auto-detect the host-only network IP from eth1 (VirtualBox/Vagrant convention).
    # On bare-metal installs, pass --public-ip explicitly.
    GIT_SERVER_IP=$(ip addr show eth1 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
    if [ -z "$GIT_SERVER_IP" ]; then
        echo "ERROR: Could not detect host-only network IP. Use --public-ip to specify manually."
        exit 1
    fi
fi

# Prompt helpers - MUST run before redirecting logs to avoid leaking secrets.
# Reads are taken from /dev/tty so they are not captured by the tee log redirect.
# Uses printf -v instead of eval for shell-injection safety.
_prompt() {
    local varname="$1"; local prompt_text="$2"; local default="$3"
    if [ -n "${!varname+x}" ] && [ -n "${!varname}" ]; then
        return
    fi
    if [ "$NON_INTERACTIVE" -eq 1 ]; then
        if [ -z "${!varname+x}" ] || [ -z "${!varname}" ]; then
            echo "ERROR: $varname required in non-interactive mode"
            exit 1
        fi
        return
    fi
    # read from /dev/tty so answers are not captured by stdout/tee
    read -rp "${prompt_text}${default:+ [${default}]}: " val < /dev/tty
    val="${val:-$default}"
    printf -v "$varname" '%s' "$val"
}

_prompt_secret() {
    local varname="$1"; local prompt_text="$2"
    if [ -n "${!varname+x}" ] && [ -n "${!varname}" ]; then
        return
    fi
    if [ "$NON_INTERACTIVE" -eq 1 ]; then
        echo "ERROR: $varname required in non-interactive mode"
        exit 1
    fi
    read -rsp "${prompt_text}: " secret < /dev/tty
    echo "" >&2
    read -rsp "Confirm ${prompt_text}: " secret2 < /dev/tty
    echo "" >&2
    if [ "$secret" != "$secret2" ]; then
        echo "ERROR: passwords do not match" >&2
        exit 1
    fi
    printf -v "$varname" '%s' "$secret"
}

# Collect required values BEFORE the log redirect below. If these prompts ran
# after `exec > tee`, the password would appear in install.log in plaintext.
_prompt GENESIS_HOST "Enter Genesis host (FQDN, required)" ""
_prompt BASIC_AUTH_EMAIL "Basic auth email" ""
if [ -n "$BASIC_AUTH_PASSWORD_FILE" ]; then
    if [ ! -r "$BASIC_AUTH_PASSWORD_FILE" ]; then
        echo "ERROR: cannot read password file $BASIC_AUTH_PASSWORD_FILE"
        exit 1
    fi
    BASIC_AUTH_PASSWORD="$(<"$BASIC_AUTH_PASSWORD_FILE")"
fi
if [ -z "${BASIC_AUTH_PASSWORD:-}" ]; then
    _prompt_secret BASIC_AUTH_PASSWORD "Basic auth password"
fi
_prompt TITAN_OWNER "Titan owner (linux username)" "$TITAN_OWNER"
_prompt TITAN_UID "Titan owner uid (numeric)" "$TITAN_UID"
# TITAN_EMAIL must be same as BASIC_AUTH_EMAIL
TITAN_EMAIL="$BASIC_AUTH_EMAIL"

# Redirect all subsequent output (stdout + stderr) to the log file AND the
# terminal. This must come AFTER the prompts above to avoid leaking secrets.
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "Juno Airgap Installer"
echo "Log: ${LOG_FILE}"

echo "[services] loading docker images"
if [ -d "docker" ]; then
    for tar_file in docker/*.tar; do
        if [ -f "${tar_file}" ]; then
            docker load -i "${tar_file}"
        fi
    done
else
    echo "WARNING: docker directory not found, skipping image load"
fi

echo "[services] starting git server + helm repo"
docker compose up -d

echo "[k3s] extracting juno-oneclick"
if [ ! -f "${ONECLICK_ARCHIVE}" ]; then
    echo "ERROR: ${ONECLICK_ARCHIVE} not found"
    exit 1
fi
rm -rf juno-oneclickfs
tar -xzf "${ONECLICK_ARCHIVE}" -C ./

echo "[k3s] verifying default route"
if ! ip route show default | grep -q .; then
    echo "ERROR: No default route found. K3s requires a default route to start."
    exit 1
fi

echo "[k3s] writing config"
# CRITICAL: config.yaml must exist BEFORE Ansible installs K3s. If K3s starts
# without embedded-registry: true, it will not serve the local image store and
# pods will fail trying to pull from docker.io (which is unreachable offline).
sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/config.yaml > /dev/null << 'EOF'
embedded-registry: true
EOF
# registries.yaml configures mirror endpoints so containerd resolves image
# pulls through the K3s embedded registry instead of the upstream registries.
sudo cp "${SCRIPT_DIR}/registries.yaml" /etc/rancher/k3s/

echo "[k3s] copying images"
sudo mkdir -p /var/lib/rancher/k3s/agent/images/
if [ -d "${SCRIPT_DIR}/images" ]; then
    image_count=$(find "${SCRIPT_DIR}/images/" -maxdepth 1 -name '*.tar' -printf '.' | wc -c)
    sudo cp "${SCRIPT_DIR}/images/"*.tar /var/lib/rancher/k3s/agent/images/
    echo "  ${image_count} tar(s) copied"
else
    echo "WARNING: images directory not found, no images to copy"
fi

echo "[ansible] running installation"
# set +e so we can inspect the exit code and retry. Ansible's first run may
# fail with a non-zero exit if K3s is still starting up — this is expected.
# The retry after 10 s handles the race condition reliably in practice.
set +e

# Write extra vars to a temp file with restricted permissions.
# Sensitive values are passed via environment variables (prefixed _JBOOT_)
# and rendered to JSON by generate-extra-vars.py, avoiding shell escaping
# issues with special characters in passwords.
TMP_EXTRA_VARS_JSON=$(mktemp -p /tmp juno-extravars.XXXX)
chmod 600 "$TMP_EXTRA_VARS_JSON"
export _JBOOT_GENESIS_HOST="$GENESIS_HOST"
export _JBOOT_BASIC_AUTH_EMAIL="$BASIC_AUTH_EMAIL"
export _JBOOT_BASIC_AUTH_PASSWORD="$BASIC_AUTH_PASSWORD"
export _JBOOT_TITAN_OWNER="$TITAN_OWNER"
export _JBOOT_TITAN_UID="$TITAN_UID"
export _JBOOT_GIT_SERVER_IP="$GIT_SERVER_IP"
# These placeholders are substituted by build-bundle.sh at bundle build time.
export _JBOOT_GENESIS_VERSION="__GENESIS_VERSION__"
export _JBOOT_ORION_VERSION="__ORION_VERSION__"

python3 "${SCRIPT_DIR}/generate-extra-vars.py" > "$TMP_EXTRA_VARS_JSON"

EXTRA_VARS_JSON="$(cat "$TMP_EXTRA_VARS_JSON")"

sudo ./juno-oneclickfs/juno-oneclick.install "./${VALUES_FILE}" "${EXTRA_VARS_JSON}"
ANSIBLE_RESULT=$?
if [ $ANSIBLE_RESULT -ne 0 ]; then
    echo "[ansible] first attempt incomplete (rc=${ANSIBLE_RESULT}) — this is expected, retrying in 10s..."
    sleep 10
    sudo ./juno-oneclickfs/juno-oneclick.install "./${VALUES_FILE}" "${EXTRA_VARS_JSON}"
    ANSIBLE_RESULT=$?
fi

# Shred the temp file to remove secrets from disk. Fall back to rm if shred
# is unavailable (e.g., on some minimal installs).
shred -u "$TMP_EXTRA_VARS_JSON" 2>/dev/null || rm -f "$TMP_EXTRA_VARS_JSON"

set -e

if [ $ANSIBLE_RESULT -ne 0 ]; then
    echo "ERROR: Installation failed (rc=${ANSIBLE_RESULT})"
    exit $ANSIBLE_RESULT
fi

echo "Installation complete. Check status: sudo k3s kubectl get pods -A"
