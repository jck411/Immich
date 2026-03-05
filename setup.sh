#!/usr/bin/env bash
# setup.sh — Idempotent bootstrap for Immich LXC 113
#
# Run inside the LXC container (pct exec 113 -- bash /opt/immich/setup.sh)
# Installs Docker CE, NVIDIA Container Toolkit, and starts Immich.

set -euo pipefail

echo "=== Immich LXC Setup ==="

# ─── Install Docker CE ───────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    echo "Installing Docker CE..."
    apt-get update
    apt-get install -y curl git ca-certificates gnupg
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    echo "Docker installed."
else
    echo "Docker already installed: $(docker --version)"
fi

# ─── Install NVIDIA Container Toolkit ────────────────────────────
if ! dpkg -l nvidia-container-toolkit &>/dev/null 2>&1; then
    echo "Installing NVIDIA Container Toolkit..."
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
        | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
        | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
        | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    apt-get update
    apt-get install -y nvidia-container-toolkit
    nvidia-ctk runtime configure --runtime=docker
    systemctl restart docker
    echo "NVIDIA Container Toolkit installed."
else
    echo "NVIDIA Container Toolkit already installed."
fi

# ─── Verify GPU ──────────────────────────────────────────────────
echo "Checking GPU access..."
if nvidia-smi &>/dev/null; then
    echo "GPU detected:"
    nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
else
    echo "WARNING: nvidia-smi not found. GPU passthrough may not be configured."
    echo "Ensure /dev/nvidia* devices are mounted in LXC config."
    echo "Immich ML will fall back to CPU mode."
fi

# ─── Create directories ─────────────────────────────────────────
echo "Creating directories..."
mkdir -p /ironwolf/Immich/upload
mkdir -p /opt/immich/postgres

# ─── Setup .env ──────────────────────────────────────────────────
if [ ! -f /opt/immich/.env ]; then
    if [ -f /opt/immich/.env.example ]; then
        DB_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)
        sed "s/CHANGE_ME_GENERATE_RANDOM_PASSWORD/${DB_PASS}/" /opt/immich/.env.example > /opt/immich/.env
        echo ".env created with generated DB password."
        echo "IMPORTANT: Save this password — it cannot be recovered."
        echo "DB_PASSWORD=${DB_PASS}"
    else
        echo "ERROR: .env.example not found in /opt/immich/. Copy repo files first."
        exit 1
    fi
else
    echo ".env already exists — skipping."
fi

# ─── Start Immich ────────────────────────────────────────────────
echo "Starting Immich..."
cd /opt/immich
docker compose up -d

echo ""
echo "=== Setup Complete ==="
echo "Immich is starting at: http://192.168.1.113:2283"
echo "Run 'docker compose logs -f' to watch startup."
echo "First startup may take a few minutes to pull images and initialize DB."
