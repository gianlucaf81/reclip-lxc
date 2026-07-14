# ReClip LXC for Proxmox VE

A [community-scripts](https://community-scripts.github.io/ProxmoxVE/)-style installer that deploys [ReClip](https://github.com/averygan/reclip) — a lightweight self-hosted media downloader (Flask + yt-dlp + ffmpeg) — into an unprivileged Debian LXC container on Proxmox VE.

## Usage

Run on the **Proxmox VE host** as root:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/gianlucaf81/reclip-lxc/main/reclip-lxc.sh)"
```

or clone/copy the script and run:

```bash
bash reclip-lxc.sh
```

The script shows a summary of the settings and asks for confirmation before creating anything.

## What it does

1. Creates an **unprivileged Debian 12/13 LXC** (auto-detects next free CTID, suitable storage, and downloads the newest Debian standard template if missing).
2. Installs ReClip in `/opt/reclip/app` with a dedicated Python venv (`flask`, `yt-dlp`, `gunicorn`) plus `ffmpeg`, running as a no-shell system user `reclip`.
3. Sets up a **systemd service** running gunicorn on `0.0.0.0:8899` (same parameters as the official Dockerfile: 1 worker, 4 threads, 600s timeout for long downloads).
4. Adds a **daily systemd timer** that updates yt-dlp (sites frequently break older versions).
5. Installs an `update-reclip` command inside the container (git pull + pip upgrade + service restart).

When finished it prints the URL: `http://<container-ip>:8899`

## Default settings

| Setting | Value |
|---|---|
| CPU | 2 cores |
| RAM | 1024 MiB |
| Disk | 8 GiB |
| Network | DHCP on `vmbr0` |
| Unprivileged | yes |
| Port | 8899 |

Customize by editing the `var_*` variables at the top of the script. For a static IP set e.g. `var_net="192.168.1.50/24"` and `var_gateway="192.168.1.1"`.

## Notes

- Downloads are stored inside the container at `/opt/reclip/app/downloads`. If you expect large downloads, increase `var_disk` or add a bind mount from the host.
- Update ReClip later from inside the container with `update-reclip`.

## License

[MIT](LICENSE)
