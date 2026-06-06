# NixOS system config — runs Omarchy v3.8.2 on top of nixpkgs.
{ config, pkgs, lib, ... }:

{
  imports = [
    ./modules/system-tweaks.nix      # Omarchy install/config/* system tweaks (sysctls, limits, sudo, gpg, …)
    ./modules/omarchy-branding.nix   # SDDM greeter theme + Plymouth boot splash
  ];

  # ── Boot: GRUB (UEFI) ──────────────────────────────────────────────────────
  # GRUB on UEFI; the ESP is mounted at /boot. NixOS lists every generation in
  # the GRUB menu, so you get bootable rollback to previous system states for
  # free (the NixOS equivalent of Omarchy's limine+snapper boot-into-snapshot).
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";          # UEFI install — no MBR target
    useOSProber = false;
    configurationLimit = 20;   # keep the GRUB menu from growing unbounded
  };
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot";
  boot.plymouth.enable = true;

  # ── Filesystems: Btrfs ──────────────────────────────────────────────────────
  # (btrfs kernel/userspace support is pulled in automatically by the
  #  fsType = "btrfs" entries in hardware-configuration.nix.)
  services.btrfs.autoScrub = {
    enable = true;
    interval = "weekly";
    fileSystems = [ "/" ];
  };
  services.fstrim.enable = true;   # periodic SSD TRIM

  # ── Swap: zram (matches the host's zram0) ──────────────────────────────────
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  # Graphics. In a plain VM (QEMU/virt-manager, VirtualBox, VMware) the guest
  # uses virtio-gpu / QXL / vmwgfx, which kernel modesetting drives out of the
  # box — so we do NOT set videoDrivers here. That's what makes it boot in a VM.
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # ┌─ NVIDIA (OPT-IN) ───────────────────────────────────────────────────────┐
  # │ Your HOST has an NVIDIA Turing+ GPU, but a VM only sees it with PCI      │
  # │ passthrough/vGPU. Loading nvidia with no NVIDIA GPU = black screen.       │
  # │ Uncomment ONLY if you're doing GPU passthrough into this VM:              │
  # │                                                                           │
  # │   services.xserver.videoDrivers = [ "nvidia" ];                           │
  # │   hardware.nvidia = {                                                      │
  # │     open = true;            # Turing+ supports the open kernel module      │
  # │     modesetting.enable = true;                                            │
  # │     powerManagement.enable = true;                                        │
  # │     nvidiaSettings = true;                                                 │
  # │   };                                                                       │
  # └───────────────────────────────────────────────────────────────────────────┘

  # ── QEMU guest rendering ──────────────────────────────────────────────────
  # In QEMU with virtio-gpu but NO 3D/virgl passthrough, wlroots/Hyprland will
  # refuse to start ("no EGL/GPU"). Allowing software rendering makes it boot
  # on llvmpipe; no hardware cursors avoids an invisible/ghost cursor in VMs.
  # (Harmless if you DO enable 3D accel — they're just fallbacks.)
  environment.sessionVariables = {
    WLR_RENDERER_ALLOW_SOFTWARE = "1";
    WLR_NO_HARDWARE_CURSORS = "1";
    # So Nautilus actually loads the python extensions (localsend/transcode):
    # installing nautilus-python isn't enough — Nautilus only scans dirs in its
    # own closure unless pointed at the loader's extension dir.
    NAUTILUS_4_EXTENSION_DIR = "${pkgs.nautilus-python}/lib/nautilus/extensions-4";
  };
  # Ensure the virtio-gpu kernel module is present early for the framebuffer.
  boot.initrd.kernelModules = [ "virtio_gpu" ];

  # ── Networking ────────────────────────────────────────────────────────────
  networking = {
    hostName = "toonix";
    networkmanager = {
      enable = true;
      wifi.backend = "iwd";
    };
    firewall = {
      enable = true;
      allowedTCPPorts = [ 53317 ]; # LocalSend
      allowedUDPPorts = [ 53317 ];
      interfaces.docker0.allowedUDPPorts = [ 53 ];
    };
  };

  # Omarchy points /etc/resolv.conf at systemd-resolved's stub, exposes a DNS
  # listener on Docker's bridge, and leaves mDNS to Avahi for printer discovery.
  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNSStubListenerExtra = "172.17.0.1";
      MulticastDNS = "no";
    };
  };

  # ── Locale / Time ─────────────────────────────────────────────────────────
  time.timeZone = "America/Chicago";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  # Redistributable firmware (wifi/gpu/microcode) — a complete daily-driver OS.
  hardware.enableRedistributableFirmware = true;
  hardware.wirelessRegulatoryDatabase = true;

  # ── Btrfs snapshots (Snapper, mirrors Omarchy) ─────────────────────────────
  # `home` = hourly timeline of user data. `root` = Omarchy's pre-update recovery
  # config (default/snapper/root: NUMBER-based, kept to 5, NO timeline). On NixOS
  # the primary system rollback is still GRUB generations; root snapper is kept
  # for fidelity + manual `snapper -c root create` before risky changes. Both use
  # the `@snapshots` subvolume mounted at /.snapshots (hardware-configuration.nix).
  services.snapper = {
    snapshotInterval = "hourly";
    cleanupInterval = "1d";
    configs.home = {
      SUBVOLUME = "/home";
      ALLOW_USERS = [ "bantam" ];
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
      TIMELINE_LIMIT_HOURLY = 5;
      TIMELINE_LIMIT_DAILY = 7;
      TIMELINE_LIMIT_WEEKLY = 2;
      TIMELINE_LIMIT_MONTHLY = 0;
      TIMELINE_LIMIT_YEARLY = 0;
    };
    # Mirrors default/snapper/root exactly (NUMBER-based, no timeline).
    configs.root = {
      SUBVOLUME = "/";
      TIMELINE_CREATE = false;   # Omarchy: pre-update recovery only, no timeline
      NUMBER_LIMIT = 5;
      NUMBER_LIMIT_IMPORTANT = 5;
    };
  };

  # ── Display: SDDM + Hyprland + UWSM ──────────────────────────────────────
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  # withUWSM = true does everything we need:
  #   • implies programs.uwsm.enable
  #   • registers Hyprland as a UWSM compositor and generates the
  #     `hyprland-uwsm.desktop` session entry (shown as "Hyprland (UWSM)")
  #   • provides the `uwsm-app` binary that all of Omarchy's bindings call
  # Omarchy normally launches via `uwsm start ... hyprland.desktop`; the NixOS
  # session uses binary mode instead, but Omarchy's in-session `uwsm-app --`
  # calls work identically — they only require being inside a UWSM session.
  # So we do NOT hand-write a session file (it would be the wrong directory
  # and duplicate the auto-generated entry).
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
    withUWSM = true;
  };

  # Hyprlock — CRITICAL: this creates the PAM service (/etc/pam.d/hyprlock) the
  # locker needs to authenticate. Without it the screen locks (idle / SUPER+CTRL+L)
  # but can NEVER unlock — you'd be locked out. Also installs the hyprlock binary
  # (so it's dropped from environment.systemPackages).
  programs.hyprlock.enable = true;

  # Screen recording: Omarchy's capture script calls gpu-screen-recorder
  # directly. NixOS has a module that installs it and creates the setcap wrapper
  # (`gsr-kms-server`) needed for promptless KMS capture.
  programs.gpu-screen-recorder.enable = true;

  # XDG portals — Hyprland portal + GTK portal (both needed by Omarchy)
  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-hyprland
      xdg-desktop-portal-gtk
    ];
    # Route portal requests explicitly (recent NixOS warns without this):
    # Hyprland's portal handles ScreenCast/Screenshot; GTK handles file dialogs.
    config.common.default = [ "hyprland" "gtk" ];
  };

  # ── Fonts (JetBrainsMono Nerd Font is Omarchy's primary font) ────────────
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji   # renamed from noto-fonts-emoji on unstable
      nerd-fonts.jetbrains-mono
      nerd-fonts.fira-code
      font-awesome
    ];
    fontconfig.enable = true;
  };

  # ── Audio (PipeWire + WirePlumber, mirrors Omarchy's setup) ──────────────
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    jack.enable = true;
    wireplumber.enable = true;
  };

  # ── Bluetooth ─────────────────────────────────────────────────────────────
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # ── User ──────────────────────────────────────────────────────────────────
  users.users.bantam = {
    isNormalUser = true;
    description = "bantam";
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "input" "docker" ];
    initialPassword = "changeme";
    shell = pkgs.bash;
  };

  # ── Sudo / Polkit / Keyring ──────────────────────────────────────────────
  security.sudo.wheelNeedsPassword = true;
  security.polkit.enable = true;
  services.gnome.gnome-keyring.enable = true;
  programs.seahorse.enable = true;

  # Omarchy's default/hypr/autostart.conf line 6 starts the polkit agent via a
  # HARDCODED Arch path: /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
  # NixOS has no /usr/lib, so we materialize exactly that path as a symlink to
  # the nixpkgs binary. This keeps Omarchy's unmodified autostart working and
  # means we do NOT need our own systemd user service (one agent, no dupes).
  systemd.tmpfiles.rules = [
    "L+ /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 - - - - ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
  ];

  # ── Misc services ────────────────────────────────────────────────────────
  services.spice-vdagentd.enable = true;     # SPICE clipboard + auto-resize
  services.qemuGuest.enable = true;          # QEMU/KVM guest integration
  services.openssh.enable = true;
  services.printing = {
    enable = true;
    browsed.enable = true;
    cups-pdf.enable = true;
    browsedConf = ''
      CreateRemotePrinters Yes
    '';
  };
  services.avahi = {
    enable = true;
    nssmdns4 = true;        # replaces the nss-mdns package (mDNS .local resolution)
  };
  services.gvfs.enable = true;   # Nautilus mounting / trash / network shares
  services.upower.enable = true; # battery info for Waybar's battery module (no-op in a VM)
  services.power-profiles-daemon.enable = true;  # `powerprofilesctl` (omarchy-menu power)
  services.fwupd.enable = true;  # NixOS-native firmware updates (`omarchy-update-firmware` shim)
  services.hardware.bolt.enable = true; # Thunderbolt security daemon (Omarchy base package: bolt)
  # NOTE: swayosd-server runs as a Home-Manager user service (services.swayosd in
  # home.nix) — there is no NixOS `services.swayosd` option. This replaces
  # Omarchy's user unit, which hardcodes /usr/bin/swayosd-server.
  virtualisation.docker = {
    enable = true;
    enableOnBoot = false; # socket-activated, matching Omarchy's Docker setup
    daemon.settings = {
      "log-driver" = "json-file";
      "log-opts" = {
        "max-size" = "10m";
        "max-file" = "5";
      };
      dns = [ "172.17.0.1" ];
      bip = "172.17.0.1/16";
    };
  };
  programs.nm-applet.enable = true;
  programs.dconf.enable = true;
  programs.system-config-printer.enable = true;

  # 1Password: Omarchy installs both the desktop app and CLI. NixOS has native
  # modules for these, which also add the setgid wrappers used by browser/CLI
  # integration. This closes the SUPER+SHIFT+/ binding and lock-on-screen-lock.
  programs._1password = {
    enable = true;
  };
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "bantam" ];
  };

  # Enable fcitx5 input method (Omarchy ships fcitx5 by default)
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [ fcitx5-gtk ];
  };

  # ── System packages ──────────────────────────────────────────────────────
  # Sourced from omarchy/install/omarchy-base.packages, mapped to nixpkgs.
  # Omitted (AUR / Arch-only / no nixpkgs equivalent):
  #   aether, asdcontrol, cliamp,
  #   kernel-modules-hook, mariadb-libs, omarchy-nvim, omarchy-walker,
  #   plocate (use mlocate), python-poetry-core, python-terminaltexteffects,
  #   sushi, tobi-try, ttf-ia-writer, yay, ufw-docker
  environment.systemPackages = with pkgs; [
    # ★ Claude Code (user-requested)
    claude-code

    # Hyprland ecosystem (Omarchy core)
    waybar
    walker
    elephant           # walker's data-provider daemon — without it walker shows NO results
    mako libnotify
    swayosd
    swaybg
    hypridle           # autostart.conf starts it; hypridle.conf drives idle/lock
    # hyprlock provided by programs.hyprlock.enable (sets up its PAM service)
    hyprsunset         # nightlight toggle (hyprsunset.conf)
    hyprpicker
    hyprshot
    grim slurp satty
    wl-clipboard cliphist
    xdg-terminal-exec
    polkit_gnome
    libsForQt5.qtstyleplugin-kvantum
    qt5.qtwayland qt6.qtwayland

    # Used by 282 omarchy-* shell scripts
    uwsm
    pamixer playerctl brightnessctl
    pavucontrol wireplumber
    networkmanagerapplet
    bluez bluez-tools
    # (fcitx5 + its gtk/qt addons come from i18n.inputMethod.fcitx5 below —
    #  `fcitx5-qt` isn't a top-level attr, and listing them here is redundant.)
    fzf jq gum bash-completion
    xmlstarlet socat
    impala iwd
    inxi mise
    libsecret gnome-keyring
    man-db less inetutils whois   # locate/updatedb come from services.locate (plocate); mlocate dropped (collided)
    luarocks

    # Terminals
    alacritty
    ghostty
    kitty
    foot
    tmux

    # CLI niceties (Omarchy bash aliases reference these)
    bat eza fd ripgrep dust zoxide starship
    btop htop fastfetch tldr
    lazygit lazydocker
    docker-compose docker-buildx
    gh
    file unzip
    dosfstools exfatprogs
    imagemagick ffmpeg
    tesseract
    yt-dlp
    woff2
    libqalculate tree-sitter
    voxtype

    # Editors / dev (Omarchy includes these via packaging/base)
    neovim
    nodejs_22 python3 ruby rustc cargo gcc gnumake clang llvm
    dotnet-runtime
    poetry

    # GUI apps from Omarchy base.
    # Browsers moved to modules/omarchy-browsers.nix: Floorp replaces Firefox,
    # Thorium replaces Chromium (both installed via home.packages there).
    nautilus
    nautilus-python          # loads Omarchy's right-click extensions (localsend/transcode)
    gvfs ffmpegthumbnailer webp-pixbuf-loader
    gnome-calculator gnome-themes-extra gnome-disk-utility yaru-theme
    libreoffice
    obsidian
    obs-studio kdePackages.kdenlive   # bare `kdenlive` attr doesn't exist on unstable
    pinta
    mpv imv
    evince
    xournalpp
    typora
    signal-desktop
    spotify
    localsend

    # Audit-driven additions (gap analysis of Omarchy config/script deps)
    gtk3                  # gtk-launch, gtk-update-icon-cache (omarchy-menu)
    desktop-file-utils    # update-desktop-database (omarchy-refresh-applications)
    v4l-utils             # v4l2-ctl (screen-recording webcam enumeration)
    libxkbcommon          # xkbcli (omarchy-menu-keybindings)
    parted                # drive helper fns in omarchy's bash framework
    util-linux            # rfkill/lsblk/wipefs (bluetooth/wifi restart, drive fns)
    opencode              # `c` alias in omarchy's bash aliases
    wl-screenrec          # additional wlroots screen recording fallback
    wiremix               # audio control panel TUI (omarchy-launch-audio, SUPER+CTRL+A)
    bluetui               # bluetooth control panel TUI (omarchy-launch-bluetooth, SUPER+CTRL+B)

    # VM guest tools
    spice-vdagent qemu-utils

    # Core CLI
    git wget curl

    # Boot splash
    plymouth
  ];

  # ── Nix settings ──────────────────────────────────────────────────────────
  # Several Omarchy apps are unfree: claude-code, obsidian, spotify, Typora,
  # 1Password, and Chromium-codec bits. Allow them for this personal VM.
  nixpkgs.config.allowUnfree = true;

  # Obsidian pins electron_40 (EOL 2026-06-30). Inert today, but once nixpkgs
  # marks electron_40 insecure this whitelist keeps obsidian evaluating/building.
  # (If a later nixpkgs bump changes the electron point-release, the build error
  #  prints the exact string to use here.) Pin a flake.lock to control timing.
  nixpkgs.config.permittedInsecurePackages = [ "electron-40.10.2" ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    trusted-users = [ "root" "bantam" ];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  system.stateVersion = "25.05";
}
