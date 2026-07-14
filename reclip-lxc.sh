#!/usr/bin/env bash

# Copyright (c) 2026
# Author: gianluca (community-scripts style)
# License: MIT
# Source: https://github.com/averygan/reclip
#
# ReClip LXC — Self-hosted media downloader (Flask + yt-dlp + ffmpeg)
# Run this on the Proxmox VE host:
#   bash reclip-lxc.sh

set -euo pipefail

# ------------------------------- Styling --------------------------------
YW=$'\033[33m'
GN=$'\033[1;92m'
RD=$'\033[01;31m'
BL=$'\033[36m'
CL=$'\033[m'
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
INFO="${BL}ℹ${CL}"

msg_info()  { echo -e " ${YW}➤${CL} $1..."; }
msg_ok()    { echo -e " ${CM} $1"; }
msg_error() { echo -e " ${CROSS} $1"; }

header_info() {
  clear
  cat <<'EOF'
    ____       ________ _
   / __ \___  / ____/ (_)___
  / /_/ / _ \/ /   / / / __ \
 / _, _/  __/ /___/ / / /_/ /
/_/ |_|\___/\____/_/_/ .___/
                    /_/
      Self-hosted Media Downloader (yt-dlp + ffmpeg)
EOF
  echo
}

error_exit() {
  msg_error "$1"
  exit 1
}

# ---------------------------- Default settings --------------------------
APP="ReClip"
var_hostname="reclip"
var_cpu="2"
var_ram="1024"        # MiB
var_disk="8"          # GiB (downloads live inside the CT)
var_bridge="vmbr0"
var_net="dhcp"        # or e.g. 192.168.1.50/24
var_gateway=""        # only needed with static IP
var_unprivileged="1"
var_port="8899"

header_info

# ------------------------------ Pre-checks ------------------------------
[[ $EUID -eq 0 ]] || error_exit "Please run this script as root on the Proxmox VE host."
command -v pveversion >/dev/null 2>&1 || error_exit "This script must run on a Proxmox VE host."

CTID=$(pvesh get /cluster/nextid)

echo -e " ${INFO} Using the following settings (edit the variables at the top of the script to change):"
echo -e "    ${BL}Container ID:${CL} ${CTID}"
echo -e "    ${BL}Hostname:${CL}     ${var_hostname}"
echo -e "    ${BL}CPU Cores:${CL}    ${var_cpu}"
echo -e "    ${BL}RAM:${CL}          ${var_ram} MiB"
echo -e "    ${BL}Disk:${CL}         ${var_disk} GiB"
echo -e "    ${BL}Network:${CL}      ${var_bridge} (${var_net})"
echo -e "    ${BL}Unprivileged:${CL} ${var_unprivileged}"
echo
read -r -p " Proceed? <y/N> " prompt
[[ ${prompt,,} =~ ^(y|yes)$ ]] || { echo "Aborted."; exit 0; }
echo

# --------------------------- Storage detection --------------------------
msg_info "Detecting storage"
TEMPLATE_STORAGE=$(pvesm status -content vztmpl | awk 'NR==2 {print $1}')
ROOTFS_STORAGE=$(pvesm status -content rootdir | awk 'NR==2 {print $1}')
[[ -n "$TEMPLATE_STORAGE" ]] || error_exit "No storage with 'vztmpl' content found."
[[ -n "$ROOTFS_STORAGE" ]] || error_exit "No storage with 'rootdir' content found."
msg_ok "Template storage: ${TEMPLATE_STORAGE} | RootFS storage: ${ROOTFS_STORAGE}"

# --------------------------- Template download --------------------------
msg_info "Updating LXC template list"
pveam update >/dev/null
msg_ok "Template list updated"

TEMPLATE=$(pveam available --section system | awk '{print $2}' | grep -E '^debian-1[23]-standard' | sort -V | tail -n1)
[[ -n "$TEMPLATE" ]] || error_exit "No Debian 12/13 standard template available via pveam."

if ! pveam list "$TEMPLATE_STORAGE" | grep -q "$TEMPLATE"; then
  msg_info "Downloading template ${TEMPLATE}"
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE" >/dev/null
  msg_ok "Template downloaded"
else
  msg_ok "Template ${TEMPLATE} already present"
fi

# --------------------------- Container creation -------------------------
if [[ "$var_net" == "dhcp" ]]; then
  NET_CONF="name=eth0,bridge=${var_bridge},ip=dhcp"
else
  NET_CONF="name=eth0,bridge=${var_bridge},ip=${var_net}"
  [[ -n "$var_gateway" ]] && NET_CONF+=",gw=${var_gateway}"
fi

msg_info "Creating LXC container ${CTID}"
pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" \
  --hostname "$var_hostname" \
  --cores "$var_cpu" \
  --memory "$var_ram" \
  --rootfs "${ROOTFS_STORAGE}:${var_disk}" \
  --net0 "$NET_CONF" \
  --unprivileged "$var_unprivileged" \
  --features nesting=1 \
  --onboot 1 \
  --tags "media;downloader;community-script-style" \
  --ostype debian >/dev/null
msg_ok "LXC container ${CTID} created"

msg_info "Starting container"
pct start "$CTID"
msg_ok "Container started"

msg_info "Waiting for network in the container"
for i in $(seq 1 30); do
  if pct exec "$CTID" -- bash -c "ping -c1 -W1 deb.debian.org >/dev/null 2>&1"; then
    break
  fi
  sleep 2
  [[ $i -eq 30 ]] && error_exit "Container did not get network connectivity."
done
msg_ok "Network is up"

# ----------------------------- Provisioning -----------------------------
msg_info "Installing dependencies (this may take a few minutes)"
pct exec "$CTID" -- bash -ec "$(cat <<'INSTALL'
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get -y -qq upgrade
apt-get -y -qq install curl ca-certificates git python3 python3-venv ffmpeg
INSTALL
)" >/dev/null
msg_ok "Dependencies installed"

msg_info "Installing ${APP}"
pct exec "$CTID" -- bash -ec "$(cat <<INSTALL
set -e
useradd -r -m -d /opt/reclip -s /usr/sbin/nologin reclip 2>/dev/null || true
git clone -q https://github.com/averygan/reclip.git /opt/reclip/app
python3 -m venv /opt/reclip/venv
/opt/reclip/venv/bin/pip install -q --upgrade pip wheel
/opt/reclip/venv/bin/pip install -q -r /opt/reclip/app/requirements.txt gunicorn yt-dlp
mkdir -p /opt/reclip/app/downloads
chown -R reclip:reclip /opt/reclip

# systemd service
cat > /etc/systemd/system/reclip.service <<'EOF'
[Unit]
Description=ReClip - Self-hosted media downloader
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=reclip
Group=reclip
WorkingDirectory=/opt/reclip/app
Environment=PATH=/opt/reclip/venv/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/opt/reclip/venv/bin/gunicorn -b 0.0.0.0:${var_port} -w 1 --threads 4 --timeout 600 app:app
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# daily yt-dlp auto-update (sites break often without it)
cat > /etc/systemd/system/reclip-ytdlp-update.service <<'EOF'
[Unit]
Description=Update yt-dlp for ReClip

[Service]
Type=oneshot
ExecStart=/opt/reclip/venv/bin/pip install -q --upgrade yt-dlp
EOF

cat > /etc/systemd/system/reclip-ytdlp-update.timer <<'EOF'
[Unit]
Description=Daily yt-dlp update for ReClip

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

# convenience updater for the app itself
cat > /usr/local/bin/update-reclip <<'EOF'
#!/usr/bin/env bash
set -e
cd /opt/reclip/app
git pull
/opt/reclip/venv/bin/pip install -q --upgrade -r requirements.txt yt-dlp
chown -R reclip:reclip /opt/reclip
systemctl restart reclip
echo "ReClip updated and restarted."
EOF
chmod +x /usr/local/bin/update-reclip

systemctl daemon-reload
systemctl enable -q --now reclip-ytdlp-update.timer
systemctl enable -q --now reclip.service
INSTALL
)" >/dev/null
msg_ok "${APP} installed and service started"

msg_info "Cleaning up"
pct exec "$CTID" -- bash -c "apt-get -y -qq autoremove && apt-get -y -qq autoclean" >/dev/null
msg_ok "Cleaned up"

# ------------------------------- Finish ---------------------------------
IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
echo
msg_ok "Completed successfully!"
echo -e " ${INFO} ${APP} is reachable at: ${GN}http://${IP}:${var_port}${CL}"
echo -e " ${INFO} Update later from inside the CT with: ${YW}update-reclip${CL}"
echo -e " ${INFO} yt-dlp auto-updates daily via systemd timer."
