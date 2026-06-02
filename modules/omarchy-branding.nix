# Omarchy login + boot branding: the SDDM greeter theme and the Plymouth boot
# splash, packaged from the bundled omarchy/ tree (Omarchy installs these to
# /usr/share via sudo; on NixOS we ship them as proper theme packages).
{ pkgs, ... }:

let
  # SDDM QML greeter theme ("omarchy"). Pure QtQuick + SddmComponents, relative
  # asset paths, uses JetBrainsMono Nerd Font (already installed) — low risk.
  omarchy-sddm-theme = pkgs.runCommandLocal "omarchy-sddm-theme" { } ''
    mkdir -p $out/share/sddm/themes
    cp -r ${../omarchy/default/sddm/omarchy} $out/share/sddm/themes/omarchy
  '';

  # Plymouth boot splash ("omarchy"). ModuleName=script (supported). The two
  # hardcoded /usr/share paths in the .plymouth must be repointed at the store.
  omarchy-plymouth-theme = pkgs.stdenvNoCC.mkDerivation {
    pname = "plymouth-omarchy-theme";
    version = "3.8.2";
    src = ../omarchy/default/plymouth;
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      mkdir -p $out/share/plymouth/themes/omarchy
      cp -r $src/* $out/share/plymouth/themes/omarchy/
      # Store sources are 0444; cp preserves that, so the copy is read-only and
      # the substituteInPlace below would fail with "Permission denied". Make
      # the tree writable first.
      chmod -R u+w $out/share/plymouth/themes/omarchy
      substituteInPlace $out/share/plymouth/themes/omarchy/omarchy.plymouth \
        --replace-fail /usr/share/plymouth/themes/omarchy \
                       $out/share/plymouth/themes/omarchy
    '';
  };
in
{
  # ── SDDM greeter ────────────────────────────────────────────────────────────
  # (enable + wayland.enable are set in configuration.nix)
  services.displayManager.sddm.theme = "omarchy";
  services.displayManager.sddm.extraPackages = with pkgs.kdePackages; [
    qtsvg
    qtmultimedia
    qtvirtualkeyboard
  ];

  # ── Plymouth boot splash ────────────────────────────────────────────────────
  # (boot.plymouth.enable is set in configuration.nix)
  boot.plymouth.theme = "omarchy";
  boot.plymouth.themePackages = [ omarchy-plymouth-theme ];
  # Quiet boot so the splash isn't trampled by kernel/udev logs (Omarchy-like).
  boot.kernelParams = [ "quiet" "splash" "rd.systemd.show_status=auto" "udev.log_level=3" ];
  boot.consoleLogLevel = 0;
  boot.initrd.verbose = false;

  environment.systemPackages = [ omarchy-sddm-theme ];
}
