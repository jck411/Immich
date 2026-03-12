# Plan: Immich Photo Library on Proxmox

Deploy Immich as a self-hosted Google Photos replacement on Proxmox — Docker-in-LXC with RTX 3070 GPU device passthrough for fast ML (face recognition, smart search). Expose via Cloudflare Tunnel. Gradually migrate 100–500 GB Google Photos library.

### Decisions
- **LXC with Docker** (not VM) — follows your Overseerr/Tautulli pattern. GPU *shared* via device passthrough, host retains access.
- **LXC 113** / IP **192.168.1.113** / port **2283**
- **Privileged LXC** — required for GPU device passthrough
- **4 cores / 8 GB RAM / 32 GB rootfs** — brings cluster to 22 cores, 49 GB of 64 GB
- **Photos on IronWolf** (`/mnt/ironwolf/Immich/`), DB + ML models on NVMe rootfs
- **`photos.jackshome.com`** via Cloudflare Tunnel
- Repo at `/home/jack/REPOS/Immich`

---

### Phase 1: Repo & Config Prep — COMPLETE

- Git repo at `/home/jack/REPOS/Immich` with docker-compose.yml, hwaccel.transcoding.yml, .env.example, setup.sh, README.md, .gitignore

### Phase 2: NVIDIA Driver on Proxmox Host — COMPLETE

- NVIDIA 570.133.07 installed via .run installer (`/root/nvidia.run`)
- Kernel 6.14.11-5-pve pinned via systemd-boot (NOT GRUB — system uses systemd-boot)
- Secure Boot disabled in BIOS (was blocking module loading with "key rejected by service")
- Modules auto-load via `/etc/modules-load.d/nvidia.conf`, nouveau blacklisted
- Boot entry at `/boot/efi/loader/entries/*-6.14.11-5-pve.conf` includes `lockdown=none`

### Phase 3: Create LXC 113 — COMPLETE

- Privileged LXC: Debian 13, 4 cores, 8 GB RAM, 32 GB rootfs, nesting=1, onboot=1
- IP 192.168.1.113, bind mount `/mnt/ironwolf` → `/ironwolf`
- GPU passthrough: cgroup2 allow majors 195 + 510, bind mounts for `/dev/nvidia*`
- Config at `/etc/pve/lxc/113.conf`

### Phase 4: LXC Setup & Immich Deploy — COMPLETE

- Docker CE 29.3.0 installed
- NVIDIA Container Toolkit installed, docker runtime configured
- NVIDIA driver 570.133.07 userspace installed inside LXC (--no-kernel-module)
- Immich v2.5.6 stack running: server (port 2283), ML (CUDA), postgres, redis
- All 4 containers healthy, `nvidia-smi` works inside ML container
- Config at `/opt/immich/` (.env, docker-compose.yml, hwaccel.transcoding.yml)

### Phase 5: Cloudflare Tunnel — COMPLETE

- Added `photos.jackshome.com → http://192.168.1.113:2283` to tunnel config
- DNS CNAME created via `cloudflared tunnel route dns`
- `https://photos.jackshome.com` returns HTTP/2 200 through Cloudflare

### Phase 6: Setup & Google Photos Migration — COMPLETE

1. Immich setup wizard completed (admin account created)
2. Google Photos migration complete:
   - 21 × ~50 GB Takeout `.tgz` archives downloaded and transferred to LXC 113
   - `immich-go` v0.31.0 used to extract and import with metadata (dates, GPS from JSON sidecars)
   - **33,954 assets imported** (31,946 photos + 2,008 videos, 271 GB)
   - 0 upload errors; 6 transient server errors on face thumbnails (cosmetic)
   - Archives cleaned up after import; 5.2 TB free on IronWolf
   - "No Faces" album created with 13,883 landscape/object/drawing photos
3. Install Immich app on Pixel 8 Pro → server URL `https://photos.jackshome.com` → enable auto-backup

### Phase 7: Documentation Updates — COMPLETE

- Updated PROXMOX/README.md, HOME_NETWORK/PROXMOX/README.md, Network_Configuration_Overview.md
- Updated jackshome.com/tunnel/config.example.yml, dns/dns_records.yml

---

### Excluded (future projects)

- Photo backup strategy (rclone to cloud, second drive, Proxmox backup)
- Immich OAuth/SSO
- NAS expansion

### Notes

- **systemd-boot, not GRUB** — Proxmox uses systemd-boot (Boot0000). Use `bootctl` commands, not `update-grub`.
- **NVIDIA driver matching** — LXC has userspace-only install (--no-kernel-module) matching host 570.133.07. On driver updates, must reinstall in both places.
- **Rootfs**: 32 GB covers DB + ML models + Docker images. Resize with `pct resize 113 rootfs +16G` if needed.
