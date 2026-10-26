#!/bin/bash
# Build an upstream QEMU aarch64 system emulator and package it as a .deb for the
# Ubuntu release this script runs on.
#
# Usage: build-deb.sh <qemu-version> <output-dir>
set -euo pipefail

VERSION="${1:?qemu version, e.g. 11.1.2}"
OUT="${2:?output directory}"
TARGETS="${QEMU_TARGETS:-aarch64-softmmu}"
PACKAGE="qemu-upstream-aarch64"
PREFIX="/opt/qemu-${VERSION}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    build-essential ninja-build pkg-config python3 python3-venv python3-pip \
    libglib2.0-dev libpixman-1-dev libfdt-dev zlib1g-dev libcap-ng-dev libattr1-dev \
    flex bison xz-utils curl ca-certificates dpkg-dev lsb-release >/dev/null

# QEMU's configure needs tomli, which is only in the standard library from Python 3.11.
if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))'; then
    apt-get install -y -qq --no-install-recommends python3-tomli >/dev/null
fi

# Compile through sccache when the caller provides it (the CI sets SCCACHE_GHA_ENABLED).
if command -v sccache >/dev/null 2>&1; then
    WRAPPERS="$(mktemp -d)"
    for compiler in cc gcc c++ g++; do
        printf '#!/bin/sh\nexec sccache /usr/bin/%s "$@"\n' "${compiler}" > "${WRAPPERS}/${compiler}"
        chmod +x "${WRAPPERS}/${compiler}"
    done
    export PATH="${WRAPPERS}:${PATH}"
fi

UBUNTU="$(lsb_release -rs)"
DEB_VERSION="${VERSION}-1~ubuntu${UBUNTU}"
WORK="$(mktemp -d)"
mkdir -p "${OUT}"
OUT="$(cd "${OUT}" && pwd)"

cd "${WORK}"
curl -sfLO "https://download.qemu.org/qemu-${VERSION}.tar.xz"
sha256sum "qemu-${VERSION}.tar.xz"
tar xf "qemu-${VERSION}.tar.xz"
cd "qemu-${VERSION}"

./configure --prefix="${PREFIX}" --target-list="${TARGETS}" \
    --enable-virtfs --disable-docs --disable-tools
ninja -C build

STAGE="${WORK}/stage"
DESTDIR="${STAGE}" ninja -C build install
mkdir -p "${STAGE}/usr/local/bin" "${STAGE}/DEBIAN"
for bin in "${STAGE}${PREFIX}"/bin/qemu-system-*; do
    ln -s "${PREFIX}/bin/$(basename "${bin}")" "${STAGE}/usr/local/bin/$(basename "${bin}")"
done

# dpkg-shlibdeps needs a debian/control next to where it runs.
mkdir -p debian
printf 'Source: %s\n\nPackage: %s\nArchitecture: amd64\n' "${PACKAGE}" "${PACKAGE}" > debian/control
DEPENDS="$(dpkg-shlibdeps -O -e "${STAGE}${PREFIX}"/bin/qemu-system-* 2>/dev/null | sed 's/^shlibs:Depends=//')"

cat > "${STAGE}/DEBIAN/control" <<EOF
Package: ${PACKAGE}
Version: ${DEB_VERSION}
Architecture: amd64
Maintainer: qemu-ubuntu-debs <noreply@github.com>
Depends: ${DEPENDS}
Section: otherosfs
Priority: optional
Homepage: https://www.qemu.org
Description: Upstream QEMU ${VERSION} system emulator (${TARGETS})
 Unmodified upstream QEMU ${VERSION}, installed in ${PREFIX} and linked in
 /usr/local/bin so it takes precedence over the distribution QEMU in PATH.
 The distribution packages are left untouched.
EOF

# GitHub release assets cannot contain "~", so the file name uses "_ubuntu" while the
# package version keeps "~ubuntu" for apt ordering.
DEB="${OUT}/${PACKAGE}_${VERSION}-1_ubuntu${UBUNTU}_amd64.deb"
dpkg-deb --build --root-owner-group "${STAGE}" "${DEB}"
dpkg-deb --info "${DEB}" | sed -n '/Package:/,/Depends:/p'
"${STAGE}${PREFIX}/bin/qemu-system-aarch64" --version | head -1
