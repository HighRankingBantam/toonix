# Home-level Omarchy features ported from install/config/*.sh,
# install/first-run/*.sh, install/login/*.sh, and default/*:
# mimetype defaults, XDG user-dirs, ~/.XCompose, GNOME/dconf defaults,
# WirePlumber drop-ins, Elephant, keyring seed, assistant skill symlinks, ~/Work.
# (Browser-default mimetypes + default-web-browser are set in the browser
#  module, since they depend on the chosen browser's .desktop name.)
{ config, pkgs, lib, ... }:

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
      "video/3gpp"        = "mpv.desktop";
      "video/3gpp2"       = "mpv.desktop";
      "video/x-ms-asf"    = "mpv.desktop";
      "video/x-ogm+ogg"   = "mpv.desktop";
      "video/x-theora+ogg" = "mpv.desktop";
      "application/ogg"   = "mpv.desktop";

      # Text/code → nvim
      "text/plain"                 = "nvim.desktop";
      "text/english"               = "nvim.desktop";
      "text/x-makefile"            = "nvim.desktop";
      "text/x-c++hdr"              = "nvim.desktop";
      "application/x-shellscript"  = "nvim.desktop";
      "text/x-chdr"                = "nvim.desktop";
      "text/x-csrc"                = "nvim.desktop";
      "text/x-c"                   = "nvim.desktop";
      "text/x-c++src"              = "nvim.desktop";
      "text/x-c++"                 = "nvim.desktop";
      "text/x-java"                = "nvim.desktop";
      "text/x-moc"                 = "nvim.desktop";
      "text/x-pascal"              = "nvim.desktop";
      "text/x-tcl"                 = "nvim.desktop";
      "text/x-tex"                 = "nvim.desktop";
      "application/xml"            = "nvim.desktop";
      "text/xml"                   = "nvim.desktop";
    };
  };

  # ── GTK/Nautilus bookmarks (user-dirs.sh) ─────────────────────────────────
  # Keep this writable and additive. Nautilus mutates the file at runtime, so a
  # declarative symlink would make the file manager feel broken.
  home.activation.omarchyGtkBookmarks =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -z "''${DRY_RUN_CMD:-}" ]; then
        gtk_dir="$HOME/.config/gtk-3.0"
        bookmarks="$gtk_dir/bookmarks"
        mkdir -p "$gtk_dir"
        touch "$bookmarks"

        for dir in Downloads Projects Pictures Videos; do
          line="file://$HOME/$dir $dir"
          grep -qxF "$line" "$bookmarks" || printf '%s\n' "$line" >> "$bookmarks"
        done
      fi
    '';

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

  # ── GNOME/dconf defaults (first-run/gnome-theme.sh + gtk-primary-paste.sh) ──
  # Omarchy sets GTK dark mode and the current theme's Yaru icon color at first
  # run. Seed those declaratively; theme switches can still mutate them later via
  # omarchy-theme-set-gnome.
  dconf.settings."org/gnome/desktop/interface" = {
    gtk-theme = "Adwaita-dark";
    color-scheme = "prefer-dark";
    icon-theme = "Yaru-yellow"; # ristretto's icons.theme
    gtk-enable-primary-paste = true;
  };

  # ── Elephant data provider (first-run/elephant.sh) ─────────────────────────
  # `omarchy-launch-walker` can start Elephant lazily, but upstream also enables
  # elephant.service. Keeping the service enabled makes `omarchy-restart-walker`
  # restart Elephant correctly instead of skipping it.
  systemd.user.services.elephant = {
    Unit = {
      Description = "Elephant data provider";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.elephant}/bin/elephant";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # ── Passwordless default keyring (login/default-keyring.sh) ────────────────
  # Preserve any user-created keyrings; only seed Omarchy's default if absent.
  home.activation.omarchyDefaultKeyring =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -z "''${DRY_RUN_CMD:-}" ]; then
        keyring_dir="$HOME/.local/share/keyrings"
        keyring_file="$keyring_dir/Default_keyring.keyring"
        default_file="$keyring_dir/default"

        mkdir -p "$keyring_dir"
        if [ ! -e "$keyring_file" ]; then
          cat > "$keyring_file" <<EOF
[keyring]
display-name=Default keyring
ctime=$(${pkgs.coreutils}/bin/date +%s)
mtime=0
lock-on-idle=false
lock-after=false
EOF
          chmod 600 "$keyring_file"
        fi

        if [ ! -e "$default_file" ]; then
          printf 'Default_keyring\n' > "$default_file"
          chmod 644 "$default_file"
        fi
        chmod 700 "$keyring_dir"
      fi
    '';

  # ── Omarchy assistant skill (config/omarchy-ai-skill.sh) ───────────────────
  # Upstream makes the Omarchy desktop skill available to common local agents on
  # first install. Keep these as runtime symlinks to the canonical Omarchy tree.
  home.activation.omarchyAISkill =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -z "''${DRY_RUN_CMD:-}" ]; then
        skill_src="$HOME/.local/share/omarchy/default/omarchy-skill"

        mkdir -p \
          "$HOME/.agents/skills" \
          "$HOME/.claude/skills" \
          "$HOME/.codex/skills" \
          "$HOME/.pi/agent/skills"

        ln -sfn "$skill_src" "$HOME/.agents/skills/omarchy"
        ln -sfn "$skill_src" "$HOME/.claude/skills/omarchy"
        ln -sfn "$skill_src" "$HOME/.codex/skills/omarchy"
        ln -sfn "$skill_src" "$HOME/.pi/agent/skills/omarchy"
      fi
    '';

  # ── ~/Work mise setup (mise-work.sh) ────────────────────────────────────────
  # Adds ./bin to PATH for anything under ~/Work; `mise trust ~/Work` once.
  home.file."Work/.mise.toml".text = ''
    [env]
    _.path = "{{ cwd }}/bin"
  '';

  # ── Voxtype default config (install/first-run/install-voxtype.hook) ────────
  # Omarchy prompts users to install/download the dictation model after login.
  # Toonix declares the binary, but keeps the model download opt-in. Seed a
  # writable config so the Waybar right-click editor and `voxtype configure`
  # both have a file to work with.
  home.activation.omarchyVoxtypeConfig =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -z "''${DRY_RUN_CMD:-}" ]; then
        voxtype_dir="$HOME/.config/voxtype"
        voxtype_config="$voxtype_dir/config.toml"
        mkdir -p "$voxtype_dir"
        if [ ! -e "$voxtype_config" ]; then
          install -m644 ${../omarchy/default/voxtype/config.toml} "$voxtype_config"
        fi
      fi
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
