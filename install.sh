#!/usr/bin/env bash
# Toonix internet bootstrap installer.
#
# Run from the booted NixOS minimal installer ISO:
#
#   curl -fsSL https://raw.githubusercontent.com/HighRankingBantam/toonix/main/install.sh | sudo bash
#   curl -fsSL https://raw.githubusercontent.com/HighRankingBantam/toonix/main/install.sh | sudo bash -s -- /dev/sda
#
# Set TOONIX_UNATTENDED=1 to skip the disk erase confirmation.
set -euo pipefail

DISK="${1:-/dev/vda}"
TOONIX_REPO="${TOONIX_REPO:-HighRankingBantam/toonix}"
TOONIX_BRANCH="${TOONIX_BRANCH:-main}"
TOONIX_ARCHIVE_URL="${TOONIX_ARCHIVE_URL:-https://github.com/${TOONIX_REPO}/archive/refs/heads/${TOONIX_BRANCH}.tar.gz}"
FLAKE_ATTR="${FLAKE_ATTR:-toonix}"

NIX_INSTALL_CONFIG="${NIX_INSTALL_CONFIG:-$(cat <<'EOF'
experimental-features = nix-command flakes
download-attempts = 10
connect-timeout = 60
stalled-download-timeout = 300
http-connections = 8
fallback = true
EOF
)}"

die() { echo "error: $*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "run as root, e.g. curl ... | sudo bash"
command -v curl >/dev/null || die "curl is required in the installer environment"
command -v tar >/dev/null || die "tar is required in the installer environment"

export NIX_CONFIG="$NIX_INSTALL_CONFIG"

WORKDIR="$(mktemp -d -t toonix-install.XXXXXX)"
cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

echo "==> downloading Toonix from $TOONIX_ARCHIVE_URL"
curl -fL --progress-bar -o "$WORKDIR/toonix.tar.gz" "$TOONIX_ARCHIVE_URL"

mkdir -p "$WORKDIR/src"
tar -xzf "$WORKDIR/toonix.tar.gz" -C "$WORKDIR/src" --strip-components=1

[ -f "$WORKDIR/src/flake.nix" ] || die "downloaded archive did not contain flake.nix"
[ -x "$WORKDIR/src/vm/install-in-vm.sh" ] || chmod +x "$WORKDIR/src/vm/install-in-vm.sh"

echo "==> starting Toonix installer for $DISK"
FLAKE_DIR="$WORKDIR/src" FLAKE_ATTR="$FLAKE_ATTR" bash "$WORKDIR/src/vm/install-in-vm.sh" "$DISK"
