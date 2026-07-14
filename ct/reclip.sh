#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/gianlucaf81/reclip-lxc/main/misc/build.func)
# Copyright (c) 2026 Gianluca Frare
# Author: gianlucaf81
# License: MIT | https://github.com/gianlucaf81/reclip-lxc/raw/main/LICENSE
# Source: https://github.com/averygan/reclip

APP="ReClip"
var_tags="${var_tags:-media;downloader}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/reclip/app ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ${APP}"
  cd /opt/reclip/app
  $STD git pull
  $STD /opt/reclip/venv/bin/pip install --upgrade -r requirements.txt gunicorn yt-dlp
  chown -R reclip:reclip /opt/reclip
  systemctl restart reclip
  msg_ok "Updated ${APP}"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8899${CL}"
