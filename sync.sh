#!/usr/bin/env bash
set -euo pipefail

cd ~/coturn/
git fetch upstream && git rebase upstream/master
cd ~/coturn/build && cmake -S .. -B . -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Release && cmake --build . --parallel "$(nproc)"
cd ~/coturn && tar -czf coturn-install-$(date +%Y%m%d-%H%M%S).tar.gz install && ls -lh coturn-install-*.tar.gz | tail -n 1


