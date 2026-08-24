#!/usr/bin/env bash
set -euo pipefail


timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

log_step() {
  echo "[$(timestamp)] [STEP] $*"
}

log_info() {
  echo "[$(timestamp)] [INFO] $*"
}

cd ~/coturn/
git fetch upstream && git pull upstream master
cd ~/coturn/build && cmake -S .. -B . -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Release && cmake --build . --parallel "$(nproc)"

  for binary in \
    turnserver \
    turnutils_uclient \
    turnutils_peer \
    turnutils_stunclient \
    turnutils_rfc5769check \
    turnutils_natdiscovery \
    turnutils_oauth
  do
    log_info "Installing ${binary} to ~/coturn/install/bin/${binary}"
    cp ~/coturn/build/bin/"${binary}" ~/coturn/install/bin/"${binary}"
  done

cd ~/coturn && tar -czf coturn-install-$(date +%Y%m%d-%H%M%S).tar.gz install && ls -lh coturn-install-*.tar.gz | tail -n 1


