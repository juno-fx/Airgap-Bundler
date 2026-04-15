#!/usr/bin/env bash
set -e

BUNDLE_DIR="/airgap-bundle"

if [ ! -d "${BUNDLE_DIR}" ]; then
    echo "ERROR: Bundle directory not found at ${BUNDLE_DIR}"
    exit 1
fi

cd "${BUNDLE_DIR}"

echo "=== Running Airgap Bundle Installation ==="
echo "Bundle directory: ${BUNDLE_DIR}"
echo "Arguments passed: $@"
echo ""

if [ $# -eq 0 ]; then
    echo "Running with default options (local registry only)..."
    ./load.sh
else
    echo "Running with options: $@"
    ./load.sh "$@"
fi