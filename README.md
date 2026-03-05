# Immich — Self-Hosted Photo Library

Google Photos replacement running on Proxmox LXC 113 with RTX 3070 GPU for ML acceleration.

## Quick Reference

| | |
|-|-|
| **LXC** | 113 (privileged, Docker, GPU passthrough) |
| **IP** | 192.168.1.113 |
| **Port** | 2283 |
| **Public URL** | https://photos.jackshome.com |
| **GPU** | RTX 3070 (shared via device passthrough) |
| **Upload Storage** | `/mnt/ironwolf/Immich/upload` (IronWolf 8TB) |
| **DB Storage** | NVMe rootfs (32 GB, local Docker storage) |
| **Resources** | 4 cores · 8 GB RAM · 2 GB swap |

## Architecture

```
Cloudflare Tunnel (photos.jackshome.com)
        │
        ▼
LXC 113 (192.168.1.113:2283)
  ├── immich_server        — Web UI + API + media processing
  ├── immich_machine_learning — Face recognition, smart search (CUDA / RTX 3070)
  ├── immich_postgres      — PostgreSQL + pgvecto.rs (vector search)
  └── immich_redis         — Cache (Valkey)

Storage:
  /ironwolf/Immich/upload  ← Photos & videos (IronWolf 8TB bind mount)
  /opt/immich/postgres     ← Database (NVMe rootfs)
  model-cache volume       ← ML models (~4 GB, Docker volume)
```

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Immich services with CUDA ML + NVENC transcoding |
| `hwaccel.transcoding.yml` | NVIDIA GPU config for video transcoding |
| `.env.example` | Template environment variables |
| `setup.sh` | Idempotent LXC bootstrap (Docker + NVIDIA toolkit + start) |
| `PLAN.md` | Full deployment plan with all phases |

## Deploy

Full step-by-step instructions are in [PLAN.md](PLAN.md). Summary:

### Prerequisites (Proxmox host)

1. **NVIDIA driver** installed on Proxmox host (`nvidia-smi` shows RTX 3070)
2. **LXC 113** created with GPU device passthrough (see LXC Config below)

### LXC Creation

```bash
pct create 113 local:vztmpl/debian-13-standard_13.0-1_amd64.tar.zst \
  --hostname immich \
  --cores 4 --memory 8192 --swap 2048 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.1.113/24,gw=192.168.1.1 \
  --storage local-lvm --rootfs local-lvm:32 \
  --mp0 /mnt/media,mp=/media \
  --mp1 /mnt/ironwolf,mp=/ironwolf \
  --unprivileged 0 \
  --features nesting=1 \
  --onboot 1 \
  --start 0
```

### GPU Passthrough (add to `/etc/pve/lxc/113.conf`)

```
lxc.cgroup2.devices.allow: c 195:* rwm
lxc.cgroup2.devices.allow: c 236:* rwm
lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file
```

### Start Immich

```bash
# Start LXC
pct start 113

# Copy files into LXC
pct exec 113 -- mkdir -p /opt/immich
# Copy docker-compose.yml, hwaccel.transcoding.yml, .env.example, setup.sh to /opt/immich/

# Run setup
pct exec 113 -- bash /opt/immich/setup.sh
```

### Verify

```bash
# Health check
curl http://192.168.1.113:2283/api/server-info/ping

# GPU in Docker
pct exec 113 -- docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi

# Logs
pct exec 113 -- docker compose -f /opt/immich/docker-compose.yml logs -f
```

## Google Photos Migration

1. Request **Google Takeout** (photos only, .tgz, 50 GB chunks)
2. Transfer archives to `/ironwolf/Immich/import/` (LAN transfer recommended)
3. Use **[immich-go](https://github.com/simulot/immich-go)** to import with metadata:
   ```bash
   immich-go upload from-google-photos /ironwolf/Immich/import/takeout-*.tgz
   ```
4. Verify: dates, GPS, face recognition, smart search

## Maintenance

```bash
# Update Immich (edit IMMICH_VERSION in .env, then):
pct exec 113 -- bash -c "cd /opt/immich && docker compose pull && docker compose up -d"

# Backup database
pct exec 113 -- docker exec immich_postgres pg_dumpall -U postgres > immich-db-backup.sql

# View logs
pct exec 113 -- docker compose -f /opt/immich/docker-compose.yml logs -f immich-server

# Restart
pct exec 113 -- docker compose -f /opt/immich/docker-compose.yml restart
```

## Related Repos

| Repo | What to update |
|------|---------------|
| [HOME_NETWORK](https://github.com/jck411/HOME_NETWORK) | IP table, PROXMOX/README.md, tunnel docs |
| [PROXMOX](https://github.com/jck411/PROXMOX) | LXC inventory, resource table |
| [jackshome.com](https://github.com/jck411/jackshome.com) | Tunnel config, DNS records |
