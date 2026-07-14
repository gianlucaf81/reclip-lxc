#!/usr/bin/env bash

# Copyright (c) 2026 Gianluca Frare
# Author: gianlucaf81
# License: MIT | https://github.com/gianlucaf81/reclip-lxc/raw/main/LICENSE
# Source: https://github.com/averygan/reclip

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y git python3 python3-venv ffmpeg
msg_ok "Installed Dependencies"

msg_info "Setting up ReClip"
useradd -r -m -d /opt/reclip -s /usr/sbin/nologin reclip
$STD git clone https://github.com/averygan/reclip.git /opt/reclip/app
python3 -m venv /opt/reclip/venv
$STD /opt/reclip/venv/bin/pip install --upgrade pip wheel
$STD /opt/reclip/venv/bin/pip install -r /opt/reclip/app/requirements.txt gunicorn yt-dlp
mkdir -p /opt/reclip/app/downloads
chown -R reclip:reclip /opt/reclip
msg_ok "Set up ReClip"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/reclip.service
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
ExecStart=/opt/reclip/venv/bin/gunicorn -b 0.0.0.0:8899 -w 1 --threads 4 --timeout 600 app:app
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/reclip-ytdlp-update.service
[Unit]
Description=Update yt-dlp for ReClip

[Service]
Type=oneshot
ExecStart=/opt/reclip/venv/bin/pip install -q --upgrade yt-dlp
EOF

cat <<EOF >/etc/systemd/system/reclip-ytdlp-update.timer
[Unit]
Description=Daily yt-dlp update for ReClip

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl enable -q --now reclip-ytdlp-update.timer
systemctl enable -q --now reclip
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
