# Copilot Instructions — Immich

Self-hosted Google Photos replacement running on Proxmox LXC 113 with RTX 3070 GPU.

## Architecture

- Docker Compose stack inside privileged LXC 113 (192.168.1.113)
- GPU shared via device passthrough (not exclusive to this container)
- Photos stored on IronWolf 8TB (`/mnt/ironwolf/Immich/`), DB on NVMe rootfs
- Exposed via Cloudflare Tunnel at `photos.jackshome.com`
- `README.md` is the source of truth for deploy steps and architecture
- `PLAN.md` tracks the phased rollout — update as phases complete

## Related Repos

| Repo | What to update |
|------|---------------|
| `~/REPOS/HOME_NETWORK` | IP table (`Network_Configuration_Overview.md`), `PROXMOX/README.md` |
| `~/REPOS/PROXMOX` | LXC inventory, resource table, LXC pattern, startup commands |
| `~/REPOS/jackshome.com` | Tunnel config (`tunnel/config.example.yml`), DNS records (`dns/dns_records.yml`) |

## What Lives Here vs Elsewhere

| Content | Location |
|---------|----------|
| Docker Compose, env config, setup script | This repo |
| Deployment plan and progress | This repo (`PLAN.md`) |
| Network topology, IP allocation | `~/REPOS/HOME_NETWORK` |
| Proxmox host config, LXC creation, GPU passthrough | `~/REPOS/PROXMOX` |
| Tunnel ingress, DNS records | `~/REPOS/jackshome.com` |
| Credentials, API keys, DB passwords | Never tracked — `.env` only (gitignored) |

## Project Structure

```
Immich/
├── docker-compose.yml          # Immich services (server, ML, postgres, redis)
├── hwaccel.transcoding.yml     # NVIDIA GPU config for video transcoding
├── .env.example                # Template environment variables
├── setup.sh                    # Idempotent LXC bootstrap script
├── README.md                   # Architecture, deploy steps, maintenance
├── PLAN.md                     # Phased deployment plan (update as phases complete)
└── .gitignore
```

## Rules

- Propagate changes to ALL affected repos when IPs, ports, or services change
- No credentials in tracked files — `.env` is gitignored, use `.env.example` for templates
- Keep `PLAN.md` current — mark phases complete, add notes on deviations
- Docker Compose should track upstream Immich releases — pin `IMMICH_VERSION` in `.env`, not in compose
- GPU config (cgroup rules, device mounts) lives in Proxmox LXC config (`/etc/pve/lxc/113.conf`), not here
- Test changes locally with `docker compose config` before deploying

## Quick Reference

- **Stack**: Docker Compose (Immich server, ML, PostgreSQL + pgvecto.rs, Valkey/Redis)
- **GPU**: RTX 3070 via NVIDIA Container Toolkit (CUDA ML image, NVENC transcoding)
- **Deploy**: `scp` files to LXC → `setup.sh` or `docker compose up -d`
- **Update**: Edit `IMMICH_VERSION` in `.env` → `docker compose pull && docker compose up -d`
- **Backup DB**: `docker exec immich_postgres pg_dumpall -U postgres > backup.sql`

## Security

- `.env` has DB password and is gitignored
- `.env.example` shows expected variables without real values
- Immich admin account created via web UI setup wizard — not stored in repo
- Cloudflare Tunnel handles HTTPS termination — no certs managed here
