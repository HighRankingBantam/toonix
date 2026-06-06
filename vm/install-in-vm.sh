#!/usr/bin/env bash
# install-in-vm.sh — run as root INSIDE the booted NixOS installer ISO to install
# Toonix onto the VM's disk from an already downloaded/copied flake tree.
#
# The internet bootstrap at ../install.sh downloads the flake and calls this
# script with FLAKE_DIR set. The local VM fallback can still mount this repo over
# 9p at /f and run this script directly.
#
# It partitions EXACTLY the Btrfs-subvolume layout the committed
# hardware-configuration.nix expects (labels BOOT + nixos), copies this flake
# into /mnt/etc/nixos, then installs from that persisted copy. No
# nixos-generate-config is needed for this known QEMU target.
#
#   mkdir -p /f && mount -t 9p -o trans=virtio,version=9p2000.L toonixflake /f
#   bash /f/vm/install-in-vm.sh                 # installs to /dev/vda
#   bash /f/vm/install-in-vm.sh /dev/sda        # override target disk
set -euo pipefail

DISK="${1:-/dev/vda}"
FLAKE_DIR="${FLAKE_DIR:-/f}"          # downloaded flake dir, or 9p mount for local fallback
FLAKE_ATTR="${FLAKE_ATTR:-toonix}"
TARGET_FLAKE_DIR="/mnt/etc/nixos"
NIXOS_INSTALL_ATTEMPTS="${NIXOS_INSTALL_ATTEMPTS:-4}"

NIX_INSTALL_CONFIG="${NIX_INSTALL_CONFIG:-$(cat <<'EOF'
experimental-features = nix-command flakes
download-attempts = 10
connect-timeout = 60
stalled-download-timeout = 600
http-connections = 2
max-substitution-jobs = 2
fallback = true
EOF
)}"

die() { echo "error: $*" >&2; exit 1; }

[ -d /sys/firmware/efi ] || die "not booted in UEFI mode — reboot the VM in UEFI (run-toonix-vm.sh uses OVMF, so this should already be UEFI)."
[ -b "$DISK" ] || die "$DISK is not a block device. Pass the right disk, e.g. bash install-in-vm.sh /dev/sda"
[ -f "$FLAKE_DIR/flake.nix" ] || die "flake not mounted at $FLAKE_DIR. Run: mkdir -p $FLAKE_DIR && mount -t 9p -o trans=virtio,version=9p2000.L toonixflake $FLAKE_DIR"
case "$NIXOS_INSTALL_ATTEMPTS" in
  ''|*[!0-9]*) die "NIXOS_INSTALL_ATTEMPTS must be a positive integer" ;;
esac
[ "$NIXOS_INSTALL_ATTEMPTS" -gt 0 ] || die "NIXOS_INSTALL_ATTEMPTS must be greater than 0"

export NIX_CONFIG="$NIX_INSTALL_CONFIG"

echo
echo "  ⚠  This will ERASE $DISK and install Toonix (flake $FLAKE_DIR#$FLAKE_ATTR)."
lsblk "$DISK" 2>/dev/null || true
# Set TOONIX_UNATTENDED=1 to skip this confirm (e.g. for a fully hands-off run).
if [ "${TOONIX_UNATTENDED:-0}" != "1" ]; then
  read -rp "  Type ERASE to continue: " ok
  [ "$ok" = "ERASE" ] || die "aborted."
fi

echo "==> cleaning any previous install mounts"
swapoff -a 2>/dev/null || true
umount -R /mnt 2>/dev/null || true

echo "==> partitioning $DISK (GPT: 2GiB ESP + rest Btrfs)"
parted -s "$DISK" -- mklabel gpt
parted -s "$DISK" -- mkpart ESP fat32 1MiB 2GiB
parted -s "$DISK" -- set 1 esp on
parted -s "$DISK" -- mkpart root btrfs 2GiB 100%
sleep 1; partprobe "$DISK" 2>/dev/null || true; sleep 1

# Partition node names differ for nvme-style names (p1) vs sd/vd (1).
case "$DISK" in *[0-9]) P="${DISK}p" ;; *) P="$DISK" ;; esac
ESP="${P}1"; ROOT="${P}2"

echo "==> formatting (ESP=$ESP label BOOT, root=$ROOT label nixos)"
mkfs.fat -F32 -n BOOT "$ESP"
mkfs.btrfs -f -L nixos "$ROOT"

echo "==> creating Btrfs subvolumes"
mount "$ROOT" /mnt
for sv in @ @home @nix @log @snapshots; do btrfs subvolume create "/mnt/$sv"; done
umount /mnt

echo "==> mounting subvolumes (compress=zstd,noatime)"
o=compress=zstd,noatime
mount -o "subvol=@,$o"          "$ROOT" /mnt
mkdir -p /mnt/{home,nix,var/log,.snapshots,boot}
mount -o "subvol=@home,$o"      "$ROOT" /mnt/home
mount -o "subvol=@nix,$o"       "$ROOT" /mnt/nix
mount -o "subvol=@log,$o"       "$ROOT" /mnt/var/log
mount -o "subvol=@snapshots,$o" "$ROOT" /mnt/.snapshots
mount "$ESP" /mnt/boot

echo "==> copying Toonix flake to $TARGET_FLAKE_DIR"
mkdir -p "$TARGET_FLAKE_DIR"
tar -C "$FLAKE_DIR" \
  --exclude='./.git' \
  --exclude='./result' \
  --exclude='./result-*' \
  --exclude='./vm/*.iso' \
  --exclude='./vm/*.iso.tmp' \
  --exclude='./vm/*.qcow2' \
  --exclude='./vm/*.fd' \
  --exclude='./vm/.iso-boot' \
  -cf - . | tar -C "$TARGET_FLAKE_DIR" -xf -

echo "==> nixos-install --flake $TARGET_FLAKE_DIR#$FLAKE_ATTR  (pulls from cache + builds custom bits; 15-40 min)"
echo "==> using conservative Nix cache settings and up to $NIXOS_INSTALL_ATTEMPTS install attempts"
# The committed hardware-configuration.nix already matches this by-label Btrfs
# layout + virtio modules, so it's used as-is. The flake is installed from
# /mnt/etc/nixos so future rebuilds work after the 9p share disappears.
# --no-root-passwd leaves root locked (no interactive prompt) — you log in as `bantam` / `changeme` (wheel
# sudo). This makes the whole install non-interactive when TOONIX_UNATTENDED=1.
for attempt in $(seq 1 "$NIXOS_INSTALL_ATTEMPTS"); do
  echo
  echo "==> nixos-install attempt $attempt/$NIXOS_INSTALL_ATTEMPTS"
  if nixos-install --flake "$TARGET_FLAKE_DIR#$FLAKE_ATTR" --no-channel-copy --no-root-passwd; then
    break
  fi

  if [ "$attempt" -eq "$NIXOS_INSTALL_ATTEMPTS" ]; then
    die "nixos-install failed after $NIXOS_INSTALL_ATTEMPTS attempts"
  fi

  echo "==> nixos-install failed; retrying after a short pause"
  sleep 20
done

cat <<'EOF'

  ✅ Install finished. Now:
     poweroff
  then on the host re-run ./vm/run-toonix-vm.sh (pick the disk in the boot menu,
  or delete vm/nixos-minimal.iso so it boots straight from disk).
  The flake lives at /etc/nixos in the installed VM, so rebuilds can use:
     sudo nixos-rebuild switch --flake /etc/nixos#toonix
  Log in at SDDM ("Hyprland (UWSM)") as  bantam / changeme.
EOF
