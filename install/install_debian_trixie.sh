#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="/usr/local/bin"
CFG_DEST="/etc/coturn/turnserver.conf"

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    echo "This script must be run as root" >&2
    exit 1
  fi
}

ensure_debian_packages() {
  export DEBIAN_FRONTEND=noninteractive

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
}

install_binaries() {
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
    fi
  done

  ln -sf "${BIN_DIR}/turnserver" "${BIN_DIR}/turnadmin"

  if [[ -f "${SRC_DIR}/turnserver.conf" ]]; then
    install -d -o turnserver -g turnserver "$(dirname "${CFG_DEST}")"
    install -o turnserver -g turnserver -m 0640 "${SRC_DIR}/turnserver.conf" "${CFG_DEST}"
  fi
}

initialize_sqlite_db() {
  install -d -o turnserver -g turnserver /var/lib/turn

  if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "sqlite3 not found; installing sqlite3 runtime package" >&2
    apt-get install -y --no-install-recommends sqlite3
  fi

  DB_PATH="/var/lib/turn/turndb"
  SCHEMA_PATH="${SRC_DIR}/schema.sql"

  if [[ -f "${SCHEMA_PATH}" ]]; then
    if [[ ! -f "${DB_PATH}" ]]; then
      sqlite3 "${DB_PATH}" < "${SCHEMA_PATH}"
      chown turnserver:turnserver "${DB_PATH}"
      chmod 0600 "${DB_PATH}"
    else
      echo "SQLite DB already exists at ${DB_PATH}; leaving it untouched"
    fi
  else
    echo "Schema file not found at ${SCHEMA_PATH}; cannot initialize SQLite DB" >&2
    exit 1
  fi
}

apply_kernel_tuning() {
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
  fi
}

install_systemd_service() {
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemctl not found; skipping systemd setup"
    return 0
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
  echo "coturn systemd service installed"
}

create_turnserver_user() {
  if ! id -u turnserver >/dev/null 2>&1; then
    useradd --system --home-dir /nonexistent --shell /usr/sbin/nologin turnserver
  fi
}

main() {
  require_root
  ensure_debian_packages
  create_turnserver_user
  install_binaries
  initialize_sqlite_db
  apply_kernel_tuning
  install_systemd_service

  echo "coturn runtime installed to ${BIN_DIR}"
  echo "Default config installed to ${CFG_DEST}"
  echo "SQLite DB initialized at /var/lib/turn/turndb"
}

main "$@"
