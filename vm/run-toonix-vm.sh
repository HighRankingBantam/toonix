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
# Tunables via env:
#   RAM=8192 CPUS=4 DISK_SIZE=40G ISO_URL=...
#   BOOT=installer|disk       # default: installer
#   HEADLESS=1                # serial installer in this terminal, no GTK window
#   CPU=host|max|qemu64       # default: host with KVM, max with TCG
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
BOOT="${BOOT:-installer}"
HEADLESS="${HEADLESS:-0}"

if [ -z "${ACCEL:-}" ]; then
  if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACCEL="kvm:tcg"
  else
    ACCEL="tcg"
  fi
fi

if [ -z "${CPU:-}" ]; then
  if [ "$ACCEL" = "tcg" ]; then
    CPU="max"
  else
    CPU="host"
  fi
fi

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

[ "$BOOT" = "installer" ] || [ "$BOOT" = "disk" ] || die "BOOT must be 'installer' or 'disk'"

if [ "$BOOT" = "installer" ]; then
  # Download the installer ISO once.
  if [ ! -f "$ISO" ]; then
    echo "==> downloading NixOS minimal ISO …"
    curl -fL --progress-bar -o "$ISO.tmp" "$ISO_URL" && mv "$ISO.tmp" "$ISO"
  fi
fi

# Create the blank disk once.
if [ ! -f "$DISK" ]; then
  echo "==> creating $DISK_SIZE qcow2 disk …"
  qemu-img create -f qcow2 "$DISK" "$DISK_SIZE" >/dev/null
fi

# Per-VM writable copy of the UEFI nvram.
[ -f "$VARS" ] || cp "$OVMF_VARS_SRC" "$VARS"

COMMON_ARGS=(
  -name toonix
  -machine "q35,accel=$ACCEL"
  -cpu "$CPU"
  -smp "$CPUS"
  -m "$RAM"
  -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
  -drive "if=pflash,format=raw,file=$VARS"
  -drive "file=$DISK,if=virtio,format=qcow2"
  -device virtio-keyboard-pci
  -device virtio-tablet-pci
  -netdev user,id=net0
  -device virtio-net-pci,netdev=net0
  -virtfs "local,path=$REPO,mount_tag=toonixflake,security_model=none,id=toonixflake"
)

if [ "$HEADLESS" = "1" ]; then
  DISPLAY_ARGS=(-display none -serial mon:stdio)
else
  DISPLAY_ARGS=(-device virtio-gpu-pci -display gtk,gl=off)
fi

if [ "$BOOT" = "disk" ]; then
  BOOT_ARGS=(-boot order=c,menu=on)
  cat <<EOF

  Booting installed Toonix disk.
  QEMU: accel=$ACCEL cpu=$CPU ram=${RAM}M cpus=$CPUS

EOF
else
  if [ "$HEADLESS" = "1" ]; then
    command -v bsdtar >/dev/null || die "HEADLESS=1 needs bsdtar/libarchive to extract the ISO kernel/initrd"

    GRUB_CFG="$(bsdtar -xOf "$ISO" EFI/BOOT/grub.cfg)"
    KERNEL_PATH="$(awk "/Installer \\(Linux LTS\\)'/{entry=1; next} entry && /^[[:space:]]*linux /{print \$2; exit}" <<<"$GRUB_CFG")"
    INITRD_PATH="$(awk "/Installer \\(Linux LTS\\)'/{entry=1; next} entry && /^[[:space:]]*initrd /{print \$2; exit}" <<<"$GRUB_CFG")"
    KERNEL_APPEND="$(awk "/Installer \\(Linux LTS\\)'/{entry=1; next} entry && /^[[:space:]]*linux /{sub(/^[[:space:]]*linux[[:space:]]+[^[:space:]]+[[:space:]]+/, \"\"); gsub(/\\$\\{isoboot\\}[[:space:]]*/, \"\"); print; exit}" <<<"$GRUB_CFG")"

    [ -n "$KERNEL_PATH" ] || die "could not find the Linux LTS kernel in $ISO"
    [ -n "$INITRD_PATH" ] || die "could not find the Linux LTS initrd in $ISO"
    KERNEL_PATH="${KERNEL_PATH#/}"; KERNEL_PATH="${KERNEL_PATH//\/\//\/}"
    INITRD_PATH="${INITRD_PATH#/}"; INITRD_PATH="${INITRD_PATH//\/\//\/}"

    BOOT_CACHE="$VMDIR/.iso-boot"
    mkdir -p "$BOOT_CACHE"
    [ -f "$BOOT_CACHE/$KERNEL_PATH" ] || bsdtar -xf "$ISO" -C "$BOOT_CACHE" "$KERNEL_PATH"
    [ -f "$BOOT_CACHE/$INITRD_PATH" ] || bsdtar -xf "$ISO" -C "$BOOT_CACHE" "$INITRD_PATH"

    BOOT_ARGS=(
      -kernel "$BOOT_CACHE/$KERNEL_PATH"
      -initrd "$BOOT_CACHE/$INITRD_PATH"
      -append "$KERNEL_APPEND console=ttyS0,115200n8 systemd.mask=display-manager.service plymouth.enable=0"
      -drive "file=$ISO,media=cdrom,readonly=on"
    )

    cat <<EOF

  Booting Toonix installer headlessly over serial.
  QEMU: accel=$ACCEL cpu=$CPU ram=${RAM}M cpus=$CPUS
  When the NixOS installer shell appears in this terminal, run:

      sudo mkdir -p /f && sudo mount -t 9p -o trans=virtio,version=9p2000.L toonixflake /f
      sudo TOONIX_UNATTENDED=1 bash /f/vm/install-in-vm.sh

  The installer copies the flake to /mnt/etc/nixos before nixos-install, so the
  installed VM can later rebuild from /etc/nixos#toonix.

EOF
  else
    BOOT_ARGS=(-cdrom "$ISO" -boot menu=on)
    cat <<EOF

  Booting Toonix VM (UEFI). The repo is shared into the guest over 9p.
  QEMU: accel=$ACCEL cpu=$CPU ram=${RAM}M cpus=$CPUS
  Inside the VM installer shell, run ONE line:

      sudo mkdir -p /f && sudo mount -t 9p -o trans=virtio,version=9p2000.L toonixflake /f && \\
        sudo TOONIX_UNATTENDED=1 bash /f/vm/install-in-vm.sh

  …or simply:

      sudo mkdir -p /f && sudo mount -t 9p -o trans=virtio,version=9p2000.L toonixflake /f
      sudo bash /f/vm/install-in-vm.sh

  After it finishes: poweroff, delete (or ignore) the ISO, re-run this script to
  boot the installed system. Login: bantam / changeme.

EOF
  fi
fi

exec qemu-system-x86_64 \
  "${COMMON_ARGS[@]}" \
  "${DISPLAY_ARGS[@]}" \
  "${BOOT_ARGS[@]}" \
  "$@"
