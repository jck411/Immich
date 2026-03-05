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

### Phase 1: Repo & Config Prep *(remote, can do now)*

1. Initialize Git repo at `/home/jack/REPOS/Immich`
2. Create `docker-compose.yml` — Immich server, ML (GPU-enabled via `deploy.resources.reservations.devices`), PostgreSQL w/ pgvecto.rs, Redis. Upload volume → `/ironwolf/Immich`, DB volumes on local Docker storage
3. Create `.env.example` with all Immich env vars (DB password, upload location, etc.)
4. Create `.gitignore`, `README.md` (architecture, LXC config, GPU setup, deploy steps)
5. Create `setup.sh` — idempotent bootstrap: install Docker CE, nvidia-container-toolkit, start services
6. **Start Google Takeout export now** — request photos-only export, 50 GB chunks. Takes hours/days to prepare.

### Phase 2: NVIDIA Driver on Proxmox Host *(web UI shell)*

> Requires host reboot — all VMs/LXCs restart (they have `onboot=1`)

7. Add Debian non-free firmware repos to `/etc/apt/sources.list`
8. `apt install nvidia-driver nvidia-smi` → reboot
9. Verify: `nvidia-smi` shows RTX 3070
10. Persist modules: add `nvidia`, `nvidia-uvm` to `/etc/modules-load.d/nvidia.conf`
11. `nvidia-modprobe -u` to ensure `/dev/nvidia-uvm` exists

### Phase 3: Create LXC 113 *(Proxmox web UI or shell)*

12. Create privileged LXC: Debian 13, 4 cores, 8 GB RAM, 32 GB rootfs, `nesting=1`, `onboot=1`, static IP 192.168.1.113, bind mounts for `/mnt/media` and `/mnt/ironwolf`
13. Add GPU device passthrough to `/etc/pve/lxc/113.conf`:
    - cgroup allow for nvidia device nodes (major 195, 236)
    - bind mount `/dev/nvidia0`, `/dev/nvidiactl`, `/dev/nvidia-uvm`, `/dev/nvidia-uvm-tools`
14. Start LXC 113

### Phase 4: LXC Setup & Immich Deploy *(LXC console via web UI)*

15. Install Docker CE (`curl -fsSL https://get.docker.com | sh`)
16. Install NVIDIA Container Toolkit — must match host driver version
17. Verify GPU in Docker: `docker run --rm --gpus all nvidia/cuda:... nvidia-smi`
18. Create directories: `/ironwolf/Immich/upload`, `/opt/immich`
19. Deploy docker-compose + `.env` to `/opt/immich/` (git clone or paste via web console)
20. `docker compose up -d` → verify `curl http://localhost:2283` returns Immich

### Phase 5: Cloudflare Tunnel *(Proxmox host shell)*

21. Add to `/root/.cloudflared/config.yml` (before catch-all):
    - `hostname: photos.jackshome.com` → `service: http://192.168.1.113:2283`
22. `cloudflared tunnel route dns home-media photos.jackshome.com`
23. `cloudflared tunnel ingress validate && systemctl restart cloudflared`
24. Test: `https://photos.jackshome.com` → Immich setup wizard

### Phase 6: Setup & Google Photos Migration

25. Complete Immich setup wizard (admin account) via web UI
26. Install Immich app on Pixel 8 Pro → server URL `https://photos.jackshome.com` → enable auto-backup
27. Google Photos migration:
    - Download Takeout archives → transfer to `/ironwolf/Immich/import/` *(best done on LAN)*
    - Use **`immich-go`** tool — handles Google Takeout JSON sidecar metadata (dates, GPS) properly
    - Verify: face recognition runs, smart search works, dates/locations correct

### Phase 7: Documentation Updates *(remote, can do now)*

28. Update `HOME_NETWORK/Network_Configuration_Overview.md` — add 192.168.1.113
29. Update `HOME_NETWORK/PROXMOX/README.md` — add LXC 113
30. Update `PROXMOX/README.md` — add to inventory + resource table
31. Update `jackshome.com/tunnel/config.example.yml` + `jackshome.com/dns/dns_records.yml`

---

### Verification

1. `nvidia-smi` on host shows RTX 3070
2. GPU visible inside Docker in LXC 113
3. `curl http://192.168.1.113:2283/api/server-info/ping` → `{"res":"pong"}`
4. `https://photos.jackshome.com` loads through tunnel
5. Face recognition processes a test photo in seconds (GPU)
6. Mobile app connects and uploads
7. `immich-go` imports a sample Takeout archive with correct metadata

### What Can Be Done Now (remote)

- **Phase 1** — repo scaffolding (all local files)
- **Phase 7** — doc updates (all local edits)
- **Request Google Takeout export** — takes hours/days, start early
- **Phase 2–5** — needs Proxmox web UI shell at `proxmox.jackshome.com` (doable remotely, but Phase 2 requires host reboot which briefly takes all services down)

### Excluded (future projects)

- Photo backup strategy (rclone to cloud, second drive, Proxmox backup)
- Immich OAuth/SSO
- NAS expansion

### Further Considerations

1. **Host reboot timing** — NVIDIA driver install (Phase 2) requires rebooting Proxmox, taking all services down briefly. Recommend doing this at a low-traffic time. All services auto-restart (`onboot=1`).
2. **NVIDIA driver version matching** — the driver inside the LXC must match the host. The recommended approach is to bind-mount the host's NVIDIA libraries into the container rather than installing separately, to avoid version skew.
3. **Rootfs size** — 32 GB should cover PostgreSQL + ML models + Docker images. If the library grows very large (500 GB+), the DB could need more space — easy to resize LXC rootfs later via `pct resize 113 rootfs +16G`.
