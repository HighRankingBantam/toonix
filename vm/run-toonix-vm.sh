#!/usr/bin/env bash
# run-toonix-vm.sh — boot a QEMU VM to install/run Toonix, with NO Nix on the host.
#
# What it does:
#   • downloads the NixOS minimal installer ISO (once),
#   • creates a blank qcow2 disk (once),
#   • boots QEMU (UEFI/OVMF) with that disk + the ISO + THIS repo shared into the
#     guest over 9p (mount tag `toonixflake`) so the flake is available inside the
#     VM with no GitHub auth,
#   • prints the one command to run inside the VM to install Toonix.
#
# Prereqs (Arch/Omarchy):  sudo pacman -S qemu-desktop edk2-ovmf
#
# Usage:
#   ./vm/run-toonix-vm.sh            # first run: boots the ISO installer
#   ./vm/run-toonix-vm.sh            # after install: boots the installed disk
#                                    #   (remove the ISO once installed, or it
#                                    #    just shows the boot menu — pick the disk)
#
# Tunables via env:  RAM=8192  CPUS=4  DISK_SIZE=40G  ISO_URL=...
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # flake root (parent of vm/)
VMDIR="$REPO/vm"
DISK="$VMDIR/toonix.qcow2"
ISO="$VMDIR/nixos-minimal.iso"
VARS="$VMDIR/OVMF_VARS.fd"

RAM="${RAM:-8192}"
CPUS="${CPUS:-4}"
DISK_SIZE="${DISK_SIZE:-40G}"
ISO_URL="${ISO_URL:-https://channels.nixos.org/nixos-unstable/latest-nixos-minimal-x86_64-linux.iso}"

die() { echo "error: $*" >&2; exit 1; }

command -v qemu-system-x86_64 >/dev/null || die "qemu not found — run: sudo pacman -S qemu-desktop edk2-ovmf"
command -v qemu-img >/dev/null            || die "qemu-img not found — run: sudo pacman -S qemu-desktop"

# Locate OVMF firmware (CODE = read-only firmware, VARS = writable nvram template).
OVMF_CODE=""; OVMF_VARS_SRC=""
for c in /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
         /usr/share/OVMF/OVMF_CODE.4m.fd /usr/share/OVMF/x64/OVMF_CODE.fd \
         /usr/share/OVMF/OVMF_CODE.fd /usr/share/qemu/edk2-x86_64-code.fd; do
  [ -e "$c" ] && { OVMF_CODE="$c"; break; }
done
for v in /usr/share/edk2/x64/OVMF_VARS.4m.fd /usr/share/edk2-ovmf/x64/OVMF_VARS.fd \
         /usr/share/OVMF/OVMF_VARS.4m.fd /usr/share/OVMF/x64/OVMF_VARS.fd \
         /usr/share/OVMF/OVMF_VARS.fd /usr/share/qemu/edk2-i386-vars.fd; do
  [ -e "$v" ] && { OVMF_VARS_SRC="$v"; break; }
done
[ -n "$OVMF_CODE" ] || die "OVMF firmware not found — run: sudo pacman -S edk2-ovmf"
[ -n "$OVMF_VARS_SRC" ] || die "OVMF_VARS not found — run: sudo pacman -S edk2-ovmf"

# Download the installer ISO once.
if [ ! -f "$ISO" ]; then
  echo "==> downloading NixOS minimal ISO …"
  curl -fL --progress-bar -o "$ISO.tmp" "$ISO_URL" && mv "$ISO.tmp" "$ISO"
fi

# Create the blank disk once.
if [ ! -f "$DISK" ]; then
  echo "==> creating $DISK_SIZE qcow2 disk …"
  qemu-img create -f qcow2 "$DISK" "$DISK_SIZE" >/dev/null
fi

# Per-VM writable copy of the UEFI nvram.
[ -f "$VARS" ] || cp "$OVMF_VARS_SRC" "$VARS"

cat <<EOF

  Booting Toonix VM (UEFI). The repo is shared into the guest over 9p.
  Inside the VM (root shell on the installer), run ONE line:

      bash <(mount -t 9p -o trans=virtio,version=9p2000.L toonixflake /mnt 2>/dev/null; \\
             mkdir -p /f && mount -t 9p -o trans=virtio,version=9p2000.L toonixflake /f && \\
             echo /f/vm/install-in-vm.sh)

  …or simply:

      mkdir -p /f && mount -t 9p -o trans=virtio,version=9p2000.L toonixflake /f
      bash /f/vm/install-in-vm.sh

  After it finishes: poweroff, delete (or ignore) the ISO, re-run this script to
  boot the installed system. Login: bantam / changeme.

EOF

exec qemu-system-x86_64 \
  -name toonix \
  -machine q35,accel=kvm:tcg \
  -cpu host \
  -smp "$CPUS" \
  -m "$RAM" \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file="$VARS" \
  -drive file="$DISK",if=virtio,format=qcow2 \
  -cdrom "$ISO" \
  -boot menu=on \
  -device virtio-gpu-pci \
  -display gtk,gl=off \
  -device virtio-keyboard-pci -device virtio-tablet-pci \
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
  -virtfs "local,path=$REPO,mount_tag=toonixflake,security_model=none,id=toonixflake" \
  "$@"
