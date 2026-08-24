#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="/usr/local/bin"
CFG_DEST="/etc/coturn/turnserver.conf"
CFG_DIST_DEST="/etc/coturn/turnserver.conf.dist"

timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

log_step() {
  echo "[$(timestamp)] [STEP] $*"
}

log_info() {
  echo "[$(timestamp)] [INFO] $*"
}

require_root() {
  log_step "Checking for root privileges"
  if [[ ${EUID} -ne 0 ]]; then
    echo "This script must be run as root" >&2
    exit 1
  fi
  log_info "Running as root"
}

ensure_debian_packages() {
  log_step "Installing Debian runtime dependencies"
  export DEBIAN_FRONTEND=noninteractive

  log_info "Updating apt package index"
  apt-get update

  # Debian trixie runtime dependencies for the current coturn build.
  # Some package names may be provided as transitional aliases depending on the
  # exact image; we install both the modern and compatibility names when present.
  apt-get install -y --no-install-recommends \
    libmicrohttpd12t64 \
    libevent-core-2.1-7t64 libevent-extra-2.1-7t64 libevent-openssl-2.1-7t64 libevent-pthreads-2.1-7t64 \
    libsqlite3-0 \
    libgnutls30t64 \
    libssl3t64 \
    zlib1g \
    libp11-kit0 libidn2-0 libunistring5 libtasn1-6 libhogweed6t64 libnettle8t64 libgmp10 libffi8
  log_info "Runtime dependencies installed"
}

install_binaries() {
  log_step "Installing coturn binaries"
  install -d "${BIN_DIR}"

  for binary in \
    turnserver \
    turnutils_uclient \
    turnutils_peer \
    turnutils_stunclient \
    turnutils_rfc5769check \
    turnutils_natdiscovery \
    turnutils_oauth
  do
    if [[ -x "${SRC_DIR}/bin/${binary}" ]]; then
      install -m 0755 "${SRC_DIR}/bin/${binary}" "${BIN_DIR}/${binary}"
      log_info "Installed ${BIN_DIR}/${binary}"
    else
      log_info "Skipped missing binary ${SRC_DIR}/bin/${binary}"
    fi
  done

  ln -sf "${BIN_DIR}/turnserver" "${BIN_DIR}/turnadmin"
  log_info "Updated symlink ${BIN_DIR}/turnadmin -> ${BIN_DIR}/turnserver"

  if [[ -f "${SRC_DIR}/turnserver.conf" ]]; then
    install -d -o turnserver -g turnserver "$(dirname "${CFG_DEST}")"

    if [[ -f "${CFG_DEST}" ]]; then
      # Preserve existing runtime config on upgrades and write the shipped
      # default to a sidecar file for manual review.
      if ! cmp -s "${SRC_DIR}/turnserver.conf" "${CFG_DEST}"; then
        install -o turnserver -g turnserver -m 0640 "${SRC_DIR}/turnserver.conf" "${CFG_DIST_DEST}"
        log_info "Existing config preserved at ${CFG_DEST}"
        log_info "New default config written to ${CFG_DIST_DEST}"
      else
        log_info "Existing config already matches packaged default"
      fi
    else
      install -o turnserver -g turnserver -m 0640 "${SRC_DIR}/turnserver.conf" "${CFG_DEST}"
      log_info "Installed config ${CFG_DEST}"
    fi
  else
    log_info "No bundled config found at ${SRC_DIR}/turnserver.conf"
  fi
}

initialize_sqlite_db() {
  log_step "Initializing SQLite database"
  install -d -o turnserver -g turnserver /var/lib/turn

  if ! command -v sqlite3 >/dev/null 2>&1; then
    log_info "sqlite3 not found; installing sqlite3 runtime package"
    apt-get install -y --no-install-recommends sqlite3
  else
    log_info "sqlite3 command already available"
  fi

  DB_PATH="/var/lib/turn/turndb"
  SCHEMA_PATH="${SRC_DIR}/schema.sql"

  if [[ -f "${SCHEMA_PATH}" ]]; then
    if [[ ! -f "${DB_PATH}" ]]; then
      sqlite3 "${DB_PATH}" < "${SCHEMA_PATH}"
      chown turnserver:turnserver "${DB_PATH}"
      chmod 0600 "${DB_PATH}"
      log_info "Created SQLite DB at ${DB_PATH}"
    else
      log_info "SQLite DB already exists at ${DB_PATH}; leaving it untouched"
    fi
  else
    echo "Schema file not found at ${SCHEMA_PATH}; cannot initialize SQLite DB" >&2
    exit 1
  fi
}

apply_kernel_tuning() {
  log_step "Applying kernel tuning"
  local sysctl_conf="/etc/sysctl.d/99-coturn-performance.conf"

  cat > "${sysctl_conf}" <<'EOF'
# coturn performance baseline for high-concurrency deployments.
net.core.rmem_max = 524288
net.core.wmem_max = 524288
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.netdev_max_backlog = 250000
EOF

  if command -v sysctl >/dev/null 2>&1; then
    sysctl -p "${sysctl_conf}" >/dev/null
    log_info "Applied sysctl settings from ${sysctl_conf}"
  else
    log_info "sysctl command not found; tuning file written but not applied"
  fi
}

install_systemd_service() {
  log_step "Installing systemd service"
  local was_active=0

  if ! command -v systemctl >/dev/null 2>&1; then
    log_info "systemctl not found; skipping systemd setup"
    return 0
  fi

  if systemctl is-active --quiet coturn.service; then
    was_active=1
    log_info "coturn.service is currently active"
  else
    log_info "coturn.service is currently inactive"
  fi

  install -d -o turnserver -g turnserver /var/lib/turn /var/log/turnserver

  cat > /etc/systemd/system/coturn.service <<'EOF'
[Unit]
Description=coTURN STUN/TURN Server
Documentation=man:coturn(1) man:turnadmin(1) man:turnserver(1)
After=network.target
Wants=network-online.target
After=network-online.target

[Service]
Type=notify
User=turnserver
Group=turnserver
RuntimeDirectory=turnserver
WorkingDirectory=/var/lib/turn
ExecStart=/usr/local/bin/turnserver -c /etc/coturn/turnserver.conf
Restart=on-failure
RestartSec=2
NoNewPrivileges=yes
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
PrivateTmp=yes
LimitNOFILE=262144
LimitNPROC=65536
TasksMax=infinity

[Install]
WantedBy=multi-user.target
Alias=turnserver.service
EOF

  systemctl daemon-reload
  systemctl enable coturn.service
  log_info "coturn.service enabled"

  if [[ ${was_active} -eq 1 ]]; then
    systemctl restart coturn.service
    log_info "coturn systemd service restarted"
  else
    log_info "coturn systemd service installed (not started)"
  fi
}

create_turnserver_user() {
  log_step "Ensuring turnserver user exists"
  if ! id -u turnserver >/dev/null 2>&1; then
    useradd --system --home-dir /nonexistent --shell /usr/sbin/nologin turnserver
    log_info "Created system user turnserver"
  else
    log_info "System user turnserver already exists"
  fi
}

main() {
  log_step "Starting coturn runtime installation"
  require_root
  ensure_debian_packages
  create_turnserver_user
  install_binaries
  initialize_sqlite_db
  apply_kernel_tuning
  install_systemd_service

  log_step "Installation finished"
  log_info "coturn runtime installed to ${BIN_DIR}"
  if [[ -f "${CFG_DEST}" ]]; then
    log_info "Runtime config path: ${CFG_DEST}"
  fi
  if [[ -f "${CFG_DIST_DEST}" ]]; then
    log_info "Packaged default config path: ${CFG_DIST_DEST}"
  fi
  log_info "SQLite DB initialized at /var/lib/turn/turndb"
}

main "$@"
