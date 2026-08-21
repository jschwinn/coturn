# coturn build dependencies for Debian trixie

This document lists the packages needed to build coturn from source on Debian trixie with systemd readiness support enabled.

## Required build packages

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  build-essential \
  cmake \
  pkg-config \
  gcc \
  make \
  libssl-dev \
  libevent-dev \
  libmicrohttpd-dev \
  libsqlite3-dev \
  libgnutls28-dev \
  libsystemd-dev \
  zlib1g-dev \
  libp11-kit-dev \
  libidn2-dev \
  libunistring-dev \
  libtasn1-6-dev \
  nettle-dev \
  libgmp-dev \
  libffi-dev
```

## Required runtime packages for the installed binary

The custom install script installs these libraries on the target Debian system:

```bash
sudo apt-get install -y --no-install-recommends \
  libmicrohttpd12t64 \
  libevent-core-2.1-7t64 libevent-extra-2.1-7t64 libevent-openssl-2.1-7t64 libevent-pthreads-2.1-7t64 \
  libsqlite3-0 \
  libgnutls30t64 \
  libssl3t64 \
  zlib1g \
  libp11-kit0 libidn2-0 libunistring5 libtasn1-6 libhogweed6t64 libnettle8t64 libgmp10 libffi8
```

## Notes

- `libsystemd-dev` is required if you want the build to include `sd_notify()` support and use `Type=notify` in the systemd unit.
- If `libsystemd-dev` is not present, the build will define `TURN_NO_SYSTEMD` and the service will not emit readiness notifications.
- The project also supports building without systemd support; in that case use `Type=simple` in the unit file.
