# Home-level Omarchy features ported from install/config/*.sh and default/*:
# mimetype defaults, XDG user-dirs, ~/.XCompose, WirePlumber drop-ins, ~/Work.
# (Browser-default mimetypes + default-web-browser are set in the browser
#  module, since they depend on the chosen browser's .desktop name.)
{ config, ... }:

let
  home = config.home.homeDirectory;
in
{
  # ── XDG user directories (user-dirs.sh) ─────────────────────────────────────
  # Omarchy keeps Downloads/Pictures/Videos and points Desktop/Templates/Public
  # at $HOME (i.e. disables them).
  xdg.userDirs = {
    enable = true;
    setSessionVariables = true;   # export XDG_*_DIR (Omarchy uses them); also silences HM's default-change warning
    createDirectories = true;
    download    = "${home}/Downloads";
    pictures    = "${home}/Pictures";
    videos      = "${home}/Videos";
    documents   = "${home}/Documents";
    music       = "${home}/Music";
    desktop     = home;
    templates   = home;
    publicShare = home;
  };

  # ── Mimetype defaults (mimetypes.sh) ────────────────────────────────────────
  # Non-browser handlers; browser/mailto live in the browser module.
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "inode/directory"            = "org.gnome.Nautilus.desktop";
      "application/pdf"            = "org.gnome.Evince.desktop";

      # Images → imv
      "image/png"  = "imv.desktop";
      "image/jpeg" = "imv.desktop";
      "image/gif"  = "imv.desktop";
      "image/webp" = "imv.desktop";
      "image/bmp"  = "imv.desktop";
      "image/tiff" = "imv.desktop";

      # Video → mpv
      "video/mp4"         = "mpv.desktop";
      "video/x-matroska"  = "mpv.desktop";
      "video/webm"        = "mpv.desktop";
      "video/quicktime"   = "mpv.desktop";
      "video/mpeg"        = "mpv.desktop";
      "video/ogg"         = "mpv.desktop";
      "video/x-msvideo"   = "mpv.desktop";
      "video/x-flv"       = "mpv.desktop";
      "video/x-ms-wmv"    = "mpv.desktop";

      # Text/code → nvim
      "text/plain"                 = "nvim.desktop";
      "application/x-shellscript"  = "nvim.desktop";
      "text/x-csrc"                = "nvim.desktop";
      "text/x-c++src"              = "nvim.desktop";
      "application/xml"            = "nvim.desktop";
      "text/xml"                   = "nvim.desktop";
    };
  };

  # ── XCompose (xcompose.sh) ──────────────────────────────────────────────────
  # CapsLock = Compose (set via hypr input kb_options=compose:caps). Pulls in
  # Omarchy's emoji compose table and adds name/email shortcuts.
  home.file.".XCompose".text = ''
    # Omarchy emoji compose table (itself includes the system "%L" locale table)
    include "${home}/.local/share/omarchy/default/xcompose"

    # Identification (Multi_key = Compose)
    <Multi_key> <space> <n> : "bantam"
    <Multi_key> <space> <e> : "nla.0105@proton.me"
  '';

  # ── WirePlumber drop-ins (default/wireplumber) ──────────────────────────────
  # ALSA soft-mixer (avoids muffled Realtek output) + Bluetooth A2DP autoconnect.
  xdg.configFile."wireplumber/wireplumber.conf.d/51-alsa-soft-mixer.conf".source =
    ../omarchy/default/wireplumber/wireplumber.conf.d/alsa-soft-mixer.conf;
  xdg.configFile."wireplumber/wireplumber.conf.d/51-bluetooth-a2dp-autoconnect.conf".source =
    ../omarchy/default/wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf;

  # ── ~/Work mise setup (mise-work.sh) ────────────────────────────────────────
  # Adds ./bin to PATH for anything under ~/Work; `mise trust ~/Work` once.
  home.file."Work/.mise.toml".text = ''
    [env]
    _.path = "{{ cwd }}/bin"
  '';

  # ── Nautilus right-click extensions (nautilus-python.sh) ────────────────────
  # "Send via LocalSend" + "Transcode" menu items. Needs pkgs.nautilus-python
  # (added in configuration.nix). The .py files use shutil.which and no-op
  # gracefully if their helper binaries aren't found, so this is safe even if
  # Nautilus doesn't load them on a given NixOS build.
  home.file.".local/share/nautilus-python/extensions/localsend.py".source =
    ../omarchy/default/nautilus-python/extensions/localsend.py;
  home.file.".local/share/nautilus-python/extensions/transcode.py".source =
    ../omarchy/default/nautilus-python/extensions/transcode.py;
}
