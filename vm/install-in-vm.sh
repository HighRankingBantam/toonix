#!/usr/bin/env bash
# install-in-vm.sh — run as root INSIDE the booted NixOS installer ISO to install
# Toonix onto the VM's disk, using the flake shared in over 9p (no GitHub auth).
#
# Assumes you booted via ../run-toonix-vm.sh (UEFI + virtio disk /dev/vda + the
# repo shared as 9p tag `toonixflake`). It partitions EXACTLY the Btrfs-subvolume
# layout the committed hardware-configuration.nix expects (labels BOOT + nixos),
# so no nixos-generate-config is needed for this known QEMU target.
#
#   mkdir -p /f && mount -t 9p -o trans=virtio,version=9p2000.L toonixflake /f
#   bash /f/vm/install-in-vm.sh                 # installs to /dev/vda
#   bash /f/vm/install-in-vm.sh /dev/sda        # override target disk
set -euo pipefail

DISK="${1:-/dev/vda}"
FLAKE_DIR="${FLAKE_DIR:-/f}"          # where the 9p share is mounted
FLAKE_ATTR="toonix"

die() { echo "error: $*" >&2; exit 1; }

[ -d /sys/firmware/efi ] || die "not booted in UEFI mode — reboot the VM in UEFI (run-toonix-vm.sh uses OVMF, so this should already be UEFI)."
[ -b "$DISK" ] || die "$DISK is not a block device. Pass the right disk, e.g. bash install-in-vm.sh /dev/sda"
[ -f "$FLAKE_DIR/flake.nix" ] || die "flake not mounted at $FLAKE_DIR. Run: mkdir -p $FLAKE_DIR && mount -t 9p -o trans=virtio,version=9p2000.L toonixflake $FLAKE_DIR"

export NIX_CONFIG="experimental-features = nix-command flakes"

echo
echo "  ⚠  This will ERASE $DISK and install Toonix (flake $FLAKE_DIR#$FLAKE_ATTR)."
lsblk "$DISK" 2>/dev/null || true
# Set TOONIX_UNATTENDED=1 to skip this confirm (e.g. for a fully hands-off run).
if [ "${TOONIX_UNATTENDED:-0}" != "1" ]; then
  read -rp "  Type ERASE to continue: " ok
  [ "$ok" = "ERASE" ] || die "aborted."
fi

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

echo "==> nixos-install --flake $FLAKE_DIR#$FLAKE_ATTR  (pulls from cache + builds custom bits; 15–40 min)"
# The committed hardware-configuration.nix already matches this by-label Btrfs
# layout + virtio modules, so it's used as-is. --no-root-passwd leaves root
# locked (no interactive prompt) — you log in as `bantam` / `changeme` (wheel
# sudo). This makes the whole install non-interactive when TOONIX_UNATTENDED=1.
nixos-install --flake "$FLAKE_DIR#$FLAKE_ATTR" --no-channel-copy --no-root-passwd

cat <<'EOF'

  ✅ Install finished. Now:
     poweroff
  then on the host re-run ./vm/run-toonix-vm.sh (pick the disk in the boot menu,
  or delete vm/nixos-minimal.iso so it boots straight from disk).
  Log in at SDDM ("Hyprland (UWSM)") as  bantam / changeme.
EOF
