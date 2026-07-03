# Baremetal overrides for a real Intel-graphics laptop.
#
# configuration.nix is tuned for a QEMU/KVM guest (virtio-gpu + forced software
# rendering + SPICE/qemu guest agents). This module is layered on top ONLY by the
# `toonix-baremetal` flake output to undo that tuning and enable real Intel GPU
# acceleration — which is what makes GTK4 clients (walker → the Omarchy menu +
# app launcher) render. Under software rendering they can't paint; on a real GPU
# they just work (see CLAUDE.md "First boot test").
#
# Install: on the laptop, partition btrfs with the @/@home/@nix/@log/@snapshots
# subvolumes (INSTALL.md), run `nixos-generate-config --root /mnt` and KEEP its
# hardware-configuration.nix, then `nixos-install --flake /mnt/etc/nixos#toonix-baremetal`.
{ lib, pkgs, ... }:
{
  # ── Undo the VM-guest tuning ───────────────────────────────────────────────
  # virtio_gpu is a QEMU device; a laptop uses i915 (Intel KMS) — in initrd for a
  # clean Plymouth handoff. mkForce because configuration.nix hard-sets virtio_gpu.
  boot.initrd.kernelModules = lib.mkForce [ "i915" ];

  # Real GPU → hardware rendering + hardware cursors (the VM forced software).
  # "0" disables both wlroots knobs. The NAUTILUS_/GSETTINGS_ vars set in
  # configuration.nix are untouched — sessionVariables from separate modules merge.
  environment.sessionVariables = {
    WLR_RENDERER_ALLOW_SOFTWARE = lib.mkForce "0";
    WLR_NO_HARDWARE_CURSORS = lib.mkForce "0";
    LIBVA_DRIVER_NAME = "iHD"; # Intel VAAPI (Gen8+); see the hyprland.conf note below
  };

  # SPICE / QEMU guest agents are pointless on bare metal.
  services.spice-vdagentd.enable = lib.mkForce false;
  services.qemuGuest.enable = lib.mkForce false;

  # ── Intel graphics (Mesa; no proprietary driver needed) ────────────────────
  # hardware.graphics.enable / enable32Bit are already on in configuration.nix.
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver # modern iHD VAAPI (Gen8 / Broadwell and newer)
    # vaapiIntel       # older i965 driver — uncomment for pre-Gen8 Intel
  ];

  # NOTE — the seeded ~/.config/hypr/hyprland.conf carries the *host machine's*
  # NVIDIA env lines (LIBVA_DRIVER_NAME=nvidia, __GLX_VENDOR_LIBRARY_NAME=nvidia,
  # NVD_BACKEND=direct). On Intel those are wrong and override the correct value
  # above. After first boot, delete those three `env =` lines from
  # ~/.config/hypr/hyprland.conf.
}
