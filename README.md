# ReClip LXC for Proxmox VE

A [community-scripts](https://community-scripts.github.io/ProxmoxVE/)-based installer that deploys [ReClip](https://github.com/averygan/reclip) — a lightweight self-hosted media downloader (Flask + yt-dlp + ffmpeg) — into an unprivileged Debian LXC container on Proxmox VE.

Built on the official community-scripts framework, so you get the familiar experience: animated spinners, **Default / Advanced Settings** dialog (CTID, hostname, resources, static IP, VLAN, DNS, SSH, storage selection, ...) and the standard update flow.

## Install

Run on the **Proxmox VE host** as root:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/gianlucaf81/reclip-lxc/main/ct/reclip.sh)"
```

Choose **Default Settings** for a one-keypress install, or **Advanced Settings** to customize everything.

When finished, ReClip is reachable at `http://<container-ip>:8899`

## Update

Run the **same command inside the container's console** — it detects the existing installation and updates ReClip (git pull + pip upgrade + service restart):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/gianlucaf81/reclip-lxc/main/ct/reclip.sh)"
```

yt-dlp also updates itself **daily** via a systemd timer (sites frequently break older versions).

## Default settings

| Setting | Value |
|---|---|
| OS | Debian 13 |
| CPU | 2 cores |
| RAM | 1024 MiB |
| Disk | 8 GiB |
| Network | DHCP on `vmbr0` |
| Unprivileged | yes |
| Port | 8899 |

## What gets installed

- ReClip in `/opt/reclip/app` with a dedicated Python venv (`flask`, `yt-dlp`, `gunicorn`) plus `ffmpeg`, running as the no-shell system user `reclip`
- systemd service `reclip` running gunicorn on `0.0.0.0:8899` (same parameters as the official Dockerfile: 1 worker, 4 threads, 600s timeout for long downloads)
- systemd timer `reclip-ytdlp-update` for daily yt-dlp upgrades

## Repository structure

```
ct/reclip.sh              # main script (run on the PVE host; also handles updates)
ct/headers/reclip         # ASCII header
install/reclip-install.sh # provisioning executed inside the container
misc/build.func           # vendored from community-scripts/ProxmoxVE (URL-patched)
misc/core.func            # vendored from community-scripts/ProxmoxVE (URL-patched)
```

`misc/build.func` and `misc/core.func` are vendored copies from [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) (MIT, © community-scripts ORG), patched only so the install script and ASCII header are fetched from this repository instead of the upstream one. All other framework parts (`error_handler.func`, `install.func`, `tools.func`, `api.func`) are loaded at runtime from upstream.

## Notes

- Downloads are stored inside the container at `/opt/reclip/app/downloads`. If you expect large downloads, pick a bigger disk in Advanced Settings or add a bind mount from the host.

## License

[MIT](LICENSE)
