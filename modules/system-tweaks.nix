# System-level tweaks ported from Omarchy's install/config/*.sh — the bits that
# aren't packages or desktop config but real OS behavior changes. Each option
# below names the Omarchy script it reproduces.
{ pkgs, ... }:

{
  # ── Kernel sysctls ──────────────────────────────────────────────────────────
  boot.kernel.sysctl = {
    # increase-file-watchers.sh — 8192 is too low for VS Code/webpack/etc.
    "fs.inotify.max_user_watches" = 524288;
    # ssh-flakiness.sh — fixes common SSH stalls behind path-MTU black holes.
    "net.ipv4.tcp_mtu_probing" = 1;
  };

  # ── systemd: bigger fd limit + fast shutdown ────────────────────────────────
  # increase-fd-limit.sh (DefaultLimitNOFILE) + fast-shutdown.sh (5s stop).
  systemd.extraConfig = ''
    DefaultLimitNOFILE=65536:524288
    DefaultTimeoutStopSec=5s
  '';
  systemd.user.extraConfig = ''
    DefaultLimitNOFILE=65536:524288
    DefaultTimeoutStopSec=5s
  '';

  # ── sudo: 10 password tries instead of 3 (increase-sudo-tries.sh) ───────────
  security.sudo.extraConfig = ''
    Defaults passwd_tries=10
  '';

  # ── Wi-Fi powersave off (wifi-powersave-rules.sh — off while on AC) ─────────
  networking.networkmanager.wifi.powersave = false;

  # ── locate / updatedb (localdb.sh + plocate-ac-only.sh) ─────────────────────
  # Omarchy uses plocate; updatedb runs on AC only there (irrelevant in a VM).
  services.locate = {
    enable = true;
    package = pkgs.plocate;
    interval = "weekly";
  };

  # ── udev: Framework 16 QMK keyboard hidraw access (default/udev) ───────────
  # Hardware-specific (no-op in a VM); ported verbatim for fidelity.
  services.udev.extraRules = ''
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="32ac", ATTRS{idProduct}=="0012", MODE="0660", TAG+="uaccess"
  '';

  # ── GPG: multiple keyservers for reliability (gpg.sh) ───────────────────────
  programs.gnupg.agent.enable = true;
  environment.etc."gnupg/dirmngr.conf".source =
    ../omarchy/default/gpg/dirmngr.conf;

  # ── Lazy-unmount gvfsd-fuse before sleep (unmount-fuse.sh) ──────────────────
  # FUSE daemons can block the kernel freeze and make suspend silently fail.
  powerManagement.powerDownCommands = ''
    while IFS=' ' read -r _ mp fstype _; do
      if [ "$fstype" = "fuse.gvfsd-fuse" ]; then
        ${pkgs.fuse3}/bin/fusermount3 -uz "$(printf '%b' "$mp")" 2>/dev/null || true
      fi
    done < /proc/mounts
  '';

  # NOTE — Omarchy tweaks intentionally NOT ported (Arch-specific or N/A in a VM):
  #   increase-lockout-limit.sh (PAM faillock — not enabled on NixOS by default)
  #   sudoless-asdcontrol.sh    (Apple Display brightness; asdcontrol unpackaged)
  #   kernel-modules-hook.sh    (Arch pacman hook; NixOS keeps modules in store)
  #   fix-powerprofilesctl-shebang.sh (Arch mise/python clash — N/A)
  #   detect-keyboard-layout.sh (copies Arch vconsole layout — we set kb_layout=us)
  #   powerprofilesctl-rules.sh / wifi udev AC-toggle (VM has no battery; the
  #     power-profiles-daemon service itself IS enabled in configuration.nix)
}
