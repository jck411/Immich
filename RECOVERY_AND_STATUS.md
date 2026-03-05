# Immich Deployment — Recovery & Status

## Current Situation: PROXMOX HOST WON'T BOOT (needs physical access)

The Proxmox host at 192.168.1.11 is currently unable to boot because the 6.17 kernel files were moved out of `/boot/` while it was the active boot kernel. The files are NOT deleted — they're in `/root/`.

---

## Recovery Steps (need monitor + keyboard on Proxmox machine)

### Option 1 — GRUB Menu (try first)
1. Power cycle the machine
2. Hold **Shift** or press **Esc** repeatedly during POST to get the GRUB menu
3. Go to **Advanced options for Proxmox VE GNU/Linux**
4. Select **Linux 6.14.11-5-pve** (this kernel is intact in /boot)
5. Once booted, restore files and rebuild GRUB:

```bash
mv /root/vmlinuz-6.17.4-2-pve.bak /boot/vmlinuz-6.17.4-2-pve
mv /root/initrd.img-6.17.4-2-pve.bak /boot/initrd.img-6.17.4-2-pve
update-grub
```

### Option 2 — If GRUB menu doesn't appear
Boot from any Linux live USB, mount the root LVM partition, and move the files back:
```bash
# Find and mount the root partition (LVM: look for pve-root or similar)
lvs  # or: lsblk
mount /dev/mapper/pve-root /mnt
mv /mnt/root/vmlinuz-6.17.4-2-pve.bak /mnt/boot/vmlinuz-6.17.4-2-pve
mv /mnt/root/initrd.img-6.17.4-2-pve.bak /mnt/boot/initrd.img-6.17.4-2-pve
umount /mnt
reboot
```

---

## What Happened (chronological)

### Goal
Install NVIDIA driver on Proxmox host for Immich ML (GPU-accelerated machine learning) in LXC 113.

### Problem 1: Kernel too new for NVIDIA driver
- Proxmox is running kernel **6.17.4-2-pve** (Debian 13 / Proxmox 9.1.4)
- NVIDIA driver 550.x (apt packages) failed DKMS build against kernel 6.17
- NVIDIA driver 570.133.07 (.run installer) also failed — kernel 6.17 is too new
- Both proprietary and open (MIT/GPL) kernel module types failed to compile

### Problem 2: Previous apt packages blocked .run installer
- First .run attempt was rejected: "alternate driver installation detected"
- Fixed by: `apt purge -y 'nvidia-*' 'libnvidia-*'`

### Problem 3: Could not boot into older kernel
- Installed **6.14.11-5-pve** kernel + headers (NVIDIA 570 should compile against this)
- `proxmox-boot-tool kernel pin` didn't work (ESP has no grub directory)
- Setting `GRUB_DEFAULT` in `/etc/default/grub` + `update-grub` didn't work
- `grub-reboot` didn't work
- System uses UEFI boot with shim → `/boot/efi/EFI/proxmox/grub.cfg` → `/boot/grub/grub.cfg`
- Something is causing GRUB to always boot 6.17 regardless of config

### Problem 4: Moved kernel files → can't boot (CURRENT STATE)
- Moved 6.17 vmlinuz + initrd from `/boot/` to `/root/` to force GRUB to skip it
- System rebooted but can't find its kernel → won't boot
- Files exist at `/root/vmlinuz-6.17.4-2-pve.bak` and `/root/initrd.img-6.17.4-2-pve.bak`

---

## What's Already Done Successfully

### NVIDIA driver built for 6.14 kernel (while running 6.17)
```bash
/root/nvidia.run --silent --no-questions --no-x-check --no-nouveau-check --kernel-name=6.14.11-5-pve
```
- This **succeeded** — driver 570.133.07 modules are compiled for 6.14.11-5-pve
- Module autoload configured: `/etc/modules-load.d/nvidia.conf` (nvidia, nvidia-uvm)
- Nouveau blacklisted: `/etc/modprobe.d/blacklist-nouveau.conf`

### Immich repo scaffolding (Phase 1 — complete)
All files created and committed at `/home/jack/REPOS/Immich/`:
- `docker-compose.yml` — Immich server, ML (CUDA), PostgreSQL+pgvecto.rs, Valkey
- `hwaccel.transcoding.yml` — NVENC GPU config
- `.env.example` — template env vars
- `setup.sh` — idempotent LXC bootstrap script
- `README.md` — full architecture and deploy guide
- `PLAN.md` — 7-phase deployment plan
- `.github/copilot-instructions.md` — agent guidelines

### Cross-repo doc updates (Phase 7 — complete, not committed)
Changes applied but NOT committed/pushed in:
- `PROXMOX/README.md` — LXC 113 added to services table
- `HOME_NETWORK/PROXMOX/README.md` — LXC 113 added
- `HOME_NETWORK/Network_Configuration_Overview.md` — IP 192.168.1.113 added
- `jackshome.com/tunnel/config.example.yml` — photos.jackshome.com ingress added
- `jackshome.com/dns/dns_records.yml` — photos subdomain added

---

## After Recovery: Resume Plan

### 1. Boot into 6.14 kernel
After GRUB menu recovery, you should be on 6.14.11-5-pve. Verify:
```bash
uname -r          # should show 6.14.11-5-pve
nvidia-smi        # should show RTX 3070, driver 570.133.07
```

### 2. Fix GRUB permanently
Figure out why GRUB ignores the default. Options:
- Remove 6.17 kernel **package** properly: `apt purge` (if re-installable)
- Or keep 6.14 pinned and investigate the boot chain

### 3. Phase 3 — Create LXC 113
```bash
pct create 113 local:vztmpl/debian-13-standard_13.0-1_amd64.tar.zst \
  --hostname immich --cores 4 --memory 8192 --swap 2048 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.1.113/24,gw=192.168.1.1 \
  --storage local-lvm --rootfs local-lvm:32 \
  --mp0 /mnt/media,mp=/media --mp1 /mnt/ironwolf,mp=/ironwolf \
  --unprivileged 0 --features nesting=1 --onboot 1 --start 0
```
Then add GPU passthrough to `/etc/pve/lxc/113.conf`:
```
lxc.cgroup2.devices.allow: c 195:* rwm
lxc.cgroup2.devices.allow: c 509:* rwm
lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file
```

### 4. Phase 4 — Deploy Immich in LXC
- `scp` repo files to LXC 113
- Run `setup.sh` (installs Docker, NVIDIA Container Toolkit, starts stack)

### 5. Phase 5 — Cloudflare Tunnel
- Add `photos.jackshome.com → http://192.168.1.113:2283` to live tunnel config at `/root/.cloudflared/config.yml`
- Restart cloudflared: `systemctl restart cloudflared`

### 6. Phase 6 — Setup & Migration
- Immich setup wizard at photos.jackshome.com
- Install mobile app
- Import Google Takeout with `immich-go`

---

## Key Files on Proxmox Host

| Path | What |
|------|------|
| `/root/nvidia.run` | NVIDIA 570.133.07 installer (keep it) |
| `/root/vmlinuz-6.17.4-2-pve.bak` | Moved 6.17 kernel — RESTORE TO /boot |
| `/root/initrd.img-6.17.4-2-pve.bak` | Moved 6.17 initrd — RESTORE TO /boot |
| `/etc/modprobe.d/blacklist-nouveau.conf` | Nouveau blacklist |
| `/etc/modules-load.d/nvidia.conf` | nvidia + nvidia-uvm autoload |
| `/etc/default/grub` | GRUB_DEFAULT set to 6.14 entry |
| `/etc/kernel/proxmox-boot-pin` | Pinned to 6.14.11-5-pve |

## Available Kernels in /boot

| Kernel | Status |
|--------|--------|
| 6.17.4-2-pve | **MOVED to /root** — must restore |
| 6.14.11-5-pve | Installed, NVIDIA driver built for this |
| 6.8.12-18-pve | Old fallback |
| 6.8.12-9-pve | Old fallback |

## System Specs
- **Host**: Proxmox 9.1.4, Ryzen 5600X, 64GB RAM
- **GPUs**: RTX 3070 (for Immich ML), Arc A310 (Plex VM 200)
- **Storage**: 980 PRO 1TB (OS), 990 PRO 2TB (downloads), IronWolf 8TB (media, 7.3TB free)
- **Access**: Proxmox web UI via `proxmox.jackshome.com` (Cloudflare Tunnel)
- **Tunnel UUID**: 7874c7c1-a308-490b-84e0-c516721e61e2
