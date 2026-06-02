# Hardware configuration — BTRFS + subvolumes (mirrors the user's real Omarchy
# disk layout, adapted for NixOS).
#
# ⚠ THIS IS A TEMPLATE. At install time, run:
#     nixos-generate-config --root /mnt
#   then REPLACE this file with the generated one (it fills in the real disk
#   UUIDs and kernel modules detected on your VM). The generated file will look
#   like this if you partition per INSTALL.md.
#
# Real host layout discovered (for reference):
#   nvme0n1p1  vfat  ESP            → /boot
#   nvme0n1p2  LUKS2 → /dev/mapper/root  btrfs
#     subvols: @→/  @home→/home  @log→/var/log  @pkg→(pacman, Arch-only)
#              swap→swapfile  .snapshots→snapper
#   + zram0 swap
# On NixOS we drop @pkg (pacman cache) and add @nix for the store.

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # ── Kernel modules ─────────────────────────────────────────────────────────
  # virtio_* = QEMU/KVM guest disk+gpu; nixos-generate-config fills the real set.
  boot.initrd.availableKernelModules = [
    "virtio_pci" "virtio_blk" "virtio_scsi" "virtio_gpu"
    "xhci_pci" "ahci" "sr_mod" "nvme" "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # ── BTRFS root with subvolumes (compress=zstd, noatime) ─────────────────────
  # All subvolumes live on one labelled btrfs filesystem ("nixos").
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@" "compress=zstd" "noatime" ];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@home" "compress=zstd" "noatime" ];
  };

  # /nix on its own subvol so it can be excluded from rollback snapshots.
  fileSystems."/nix" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@nix" "compress=zstd" "noatime" ];
  };

  fileSystems."/var/log" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@log" "compress=zstd" "noatime" ];
  };

  fileSystems."/.snapshots" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@snapshots" "compress=zstd" "noatime" ];
  };

  # ── EFI System Partition ────────────────────────────────────────────────────
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  # ── Swap: zram is configured in configuration.nix (zramSwap.enable). ───────
  # Add a real swap partition/file here only if you want hibernation.
  swapDevices = [ ];

  # ┌─ LUKS (OPT-IN) ─────────────────────────────────────────────────────────┐
  # │ Your real host encrypts root (LUKS2 → /dev/mapper/root). For a test VM   │
  # │ we default to UNENCRYPTED so boot needs no passphrase. To faithfully     │
  # │ reproduce the encrypted setup, partition the root as LUKS, then:          │
  # │                                                                           │
  # │   boot.initrd.luks.devices."root" = {                                     │
  # │     device = "/dev/disk/by-uuid/<LUKS-PARTITION-UUID>";                    │
  # │     allowDiscards = true;   # SSD TRIM through the encrypted layer        │
  # │   };                                                                       │
  # │                                                                           │
  # │ and point the btrfs fileSystems above at /dev/mapper/root instead of      │
  # │ /dev/disk/by-label/nixos. `nixos-generate-config` writes this for you if  │
  # │ you've already opened the LUKS device before running it.                  │
  # └───────────────────────────────────────────────────────────────────────────┘

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
