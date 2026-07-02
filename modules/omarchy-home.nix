# Installs Omarchy's configs + runtime state into $HOME as WRITABLE files.
#
# Why activation-copy instead of home.file symlinks?
#   Omarchy is a self-mutating system: 282 `omarchy-*` scripts rewrite
#   ~/.config at runtime (theme switching does `rm -rf current/ && mv`,
#   relinks ~/.config/mako/config, writes ~/.local/state/omarchy/toggles, …).
#   Read-only Nix-store symlinks would make all of that fail. So we mirror
#   what Omarchy's real installer (install/config/config.sh) does:
#       cp -R ~/.local/share/omarchy/config/* ~/.config/
#   …then chmod +w, then seed the runtime-state dirs. Result: Omarchy behaves
#   exactly as on Arch (theme menu, toggles, hooks all work in the VM).
#
# Symlink handling: we copy with `cp -Rf` (NOT `-L`). Omarchy's hypr/shaders/
# are symlinks into /usr/share/aether (an AUR package with no nixpkgs build),
# so they're dangling here — dereferencing would abort activation. Preserving
# them as-is is harmless (Hyprland only reads a shader when one is toggled on).
#
# Reproducibility note: stock app configs are re-copied every activation
# (cheap, Omarchy-owned, static). Runtime state (current theme, user theme
# library, toggle flags) is seeded only-if-absent so `nixos-rebuild` never
# clobbers a theme you switched to inside the VM.
{ config, pkgs, lib, ... }:

let
  cfgSrc        = ../omarchy/config;          # stock per-app configs
  migrationsDir = ../omarchy/migrations;       # 325 migration scripts (Arch-only)
  userHypr      = ../user-configs/hypr;        # user's real customizations
  userUwsm      = ../user-configs/uwsm;
  userWalker    = ../user-configs/walker;
  userAlacritty = ../user-configs/alacritty;
  userOpencode  = ../user-configs/opencode;    # permission policy + share/autoupdate prefs
  userTmux      = ../user-configs/tmux;        # user keybindings (M-Enter splits, ? popup)
  userBtop      = ../user-configs/btop;        # proc_per_core / proc_follow_detailed
  userAutostart = ../user-configs/autostart;   # 1password --silent (NixOS-pathed Exec)
  userXdgTerms  = ../user-configs/xdg-terminals.list;  # Ghostty is the user's default terminal
  userZen       = ../user-configs/omarchy-zen;         # zen-theme-map/zen-chrome (theme-set hook data)
  userZenLib    = ../user-configs/catppuccin-zen;      # ~/.local/share/catppuccin-zen palette library
  userThemes    = ../user-configs/omarchy-themes;     # installed alt themes (~229M)
  userHooks     = ../user-configs/omarchy-hooks;       # theme-set hook etc.
  curTheme      = ../user-configs/omarchy-current;     # rendered ristretto seed
  appsSrc       = ../omarchy/applications;             # custom launchers + hidden/ menu-declutter + webapp icons
  omaRoot       = ../omarchy;                          # tree root (icon.txt/logo.txt branding, toggle flags)
  fc            = "${pkgs.fontconfig}/bin/fc-cache";
in
{
  home.activation.omarchyInstall =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # Skip on `home-manager build`/dry-run (DRY_RUN_CMD is non-empty then).
      if [ -n "''${DRY_RUN_CMD:-}" ]; then
        echo "(dry-run) would install Omarchy configs into \$HOME"
      else
        cfg="$HOME/.config"
        mkdir -p "$cfg"

        # Make copied store files writable, WITHOUT touching symlinks
        # (the dangling aether shader links would otherwise error).
        makeWritable() {
          find "$1" \( -type d -o -type f \) -exec chmod u+w {} + 2>/dev/null || true
        }

        # ── 1. Stock per-app configs → ~/.config (writable) ───────────────
        # Skip: omarchy (runtime state, seeded below), git (home-manager owns
        # it), chromium (browser rewrites it), the dirs overridden with the
        # user's real configs (hypr/uwsm/walker/alacritty), and systemd —
        # home-manager owns ~/.config/systemd/user (e.g. swayosd.service), so a
        # `rm -rf ~/.config/systemd` here would clobber HM's units every rebuild.
        # The stock omarchy systemd units are laptop-only (battery/recover) or
        # superseded by HM (swayosd-server), so nothing is lost by skipping them.
        for entry in "${cfgSrc}"/*; do
          name="$(basename "$entry")"
          case "$name" in
            omarchy|git|chromium|hypr|uwsm|walker|alacritty|systemd) continue ;;
          esac
          rm -rf "$cfg/$name"
          cp -Rf "$entry" "$cfg/$name"
          makeWritable "$cfg/$name"
        done

        # ── 2. User's real customizations (override stock) ────────────────
        for pair in \
          "${userHypr}:hypr" \
          "${userUwsm}:uwsm" \
          "${userWalker}:walker" \
          "${userAlacritty}:alacritty" \
          "${userOpencode}:opencode" \
          "${userTmux}:tmux" \
          "${userBtop}:btop"; do
          src="''${pair%%:*}"; dst="''${pair##*:}"
          rm -rf "$cfg/$dst"
          cp -Rf "$src" "$cfg/$dst"
          makeWritable "$cfg/$dst"
        done

        # ── 2b. Single-file / merge overlays (don't clobber stock dirs) ────
        # Ghostty first in the terminal preference order (user's live setup;
        # bindings.conf launches via xdg-terminal-exec, so this picks the
        # terminal SUPER+RETURN opens).
        install -m644 "${userXdgTerms}" "$cfg/xdg-terminals.list"
        # Merge the user's autostart entries into the stock autostart dir
        # (replacing it wholesale would drop Omarchy's own entries).
        mkdir -p "$cfg/autostart"
        for f in "${userAutostart}"/*.desktop; do
          [ -e "$f" ] && install -m644 "$f" "$cfg/autostart/$(basename "$f")"
        done

        # ── 3. ~/.config/omarchy runtime dir (themed/, extensions/, hooks/) ─
        mkdir -p "$cfg/omarchy"
        cp -Rf "${cfgSrc}/omarchy/." "$cfg/omarchy/" 2>/dev/null || true
        # User's theme-set hook + post-boot hooks
        mkdir -p "$cfg/omarchy/hooks"
        cp -Rf "${userHooks}/." "$cfg/omarchy/hooks/" 2>/dev/null || true
        # User's Zen Browser theming data (zen-theme-map.conf, zen-chrome/, …).
        # Zen itself isn't packaged (user's primary is Floorp); the theme-set
        # hook that consumes these degrades to a non-fatal "Hook failed" line.
        cp -Rf "${userZen}/." "$cfg/omarchy/" 2>/dev/null || true
        # Branding (branding.sh): fastfetch sources branding/about.txt for its logo.
        mkdir -p "$cfg/omarchy/branding"
        cp -f "${omaRoot}/icon.txt" "$cfg/omarchy/branding/about.txt"      2>/dev/null || true
        cp -f "${omaRoot}/logo.txt" "$cfg/omarchy/branding/screensaver.txt" 2>/dev/null || true
        # Make the freshly-copied bits writable, but prune themes/ (229M) and the
        # runtime current/ — those are handled by steps 4 & 5, and descending into
        # them here would needlessly re-chmod thousands of files every rebuild.
        find "$cfg/omarchy" \
          -path "$cfg/omarchy/themes"  -prune -o \
          -path "$cfg/omarchy/current" -prune -o \
          \( -type d -o -type f \) -exec chmod u+w {} + 2>/dev/null || true

        # ── 4. Installed theme library (seed once; ~229M, preserves edits) ─
        mkdir -p "$cfg/omarchy/themes"
        if [ -z "$(ls -A "$cfg/omarchy/themes" 2>/dev/null)" ]; then
          cp -Rf "${userThemes}/." "$cfg/omarchy/themes/" 2>/dev/null || true
          makeWritable "$cfg/omarchy/themes"
        fi

        # ── 5. Active theme (ristretto). Seed only if no theme set yet, so
        #       switching themes inside the VM survives `nixos-rebuild`. ─────
        if [ ! -e "$cfg/omarchy/current/theme.name" ]; then
          mkdir -p "$cfg/omarchy/current"
          rm -rf "$cfg/omarchy/current/theme"
          cp -Rf "${curTheme}/theme" "$cfg/omarchy/current/theme"
          cp -f  "${curTheme}/theme.name" "$cfg/omarchy/current/theme.name"
          makeWritable "$cfg/omarchy/current"
          # Background symlink (Omarchy points current/background at a file in
          # the theme's backgrounds/). Prefer 0-launch.png, else first file.
          bg="$cfg/omarchy/current/theme/backgrounds/0-launch.png"
          if [ ! -e "$bg" ]; then
            bg="$(find "$cfg/omarchy/current/theme/backgrounds" -maxdepth 1 -type f | sort | head -1)"
          fi
          [ -n "$bg" ] && ln -sfn "$bg" "$cfg/omarchy/current/background"
        fi

        # ── 6. Theme-managed symlinks (Omarchy's install/config/theme.sh) ──
        mkdir -p "$cfg/btop/themes"
        ln -sfn "$cfg/omarchy/current/theme/btop.theme" "$cfg/btop/themes/current.theme"
        mkdir -p "$cfg/mako"
        ln -sfn "$cfg/omarchy/current/theme/mako.ini" "$cfg/mako/config"

        # ── 7. Runtime state: toggles + pre-marked migrations ─────────────
        mkdir -p "$HOME/.local/state/omarchy/toggles/hypr"
        # toggles flags.conf (omarchy-toggles.sh) — hyprland.conf sources
        # ~/.local/state/omarchy/toggles/hypr/*.conf; keep at least this file.
        cp -f "${omaRoot}/default/hypr/toggles/flags.conf" \
              "$HOME/.local/state/omarchy/toggles/hypr/flags.conf" 2>/dev/null || true
        mkdir -p "$HOME/.local/state/omarchy/migrations/skipped"
        # Mark every Arch migration as already-applied so a future
        # `omarchy update` never tries to replay pacman/sudo migrations.
        for m in "${migrationsDir}"/*.sh; do
          [ -e "$m" ] && touch "$HOME/.local/state/omarchy/migrations/$(basename "$m")"
        done

        # ── 7b. Zen palette library (~/.local/share/catppuccin-zen) ────────
        # Data the user's theme-set hook feeds Zen Browser; seed once,
        # writable (the hook's updater can git-pull/regenerate it).
        if [ ! -d "$HOME/.local/share/catppuccin-zen" ]; then
          mkdir -p "$HOME/.local/share"
          cp -Rf "${userZenLib}" "$HOME/.local/share/catppuccin-zen"
          makeWritable "$HOME/.local/share/catppuccin-zen"
        fi

        # ── 8. Omarchy's custom Waybar glyph font ─────────────────────────
        mkdir -p "$HOME/.local/share/fonts"
        cp -f "${cfgSrc}/omarchy.ttf" "$HOME/.local/share/fonts/omarchy.ttf" 2>/dev/null || true
        chmod u+w "$HOME/.local/share/fonts/omarchy.ttf" 2>/dev/null || true
        ${fc} -f "$HOME/.local/share/fonts" >/dev/null 2>&1 || true

        # ── 9. Desktop entries: custom launchers + menu declutter + icons ──
        # Omarchy ships Alacritty/imv/mpv/typora launchers, a hidden/ set of
        # Hidden=true entries that remove clutter (avahi-discover, java tools,
        # fcitx config tools, electron stubs…) from the app launcher, and webapp
        # icons. `install -m644` writes them writable (store files are 0444) and
        # never touches the home-manager-managed thorium-browser/chromium entries
        # (different basenames). Hidden entries shadow the system ones by name.
        appdst="$HOME/.local/share/applications"
        mkdir -p "$appdst/icons"
        for f in "${appsSrc}"/*.desktop "${appsSrc}"/hidden/*.desktop; do
          [ -e "$f" ] && install -m644 "$f" "$appdst/$(basename "$f")"
        done
        for f in "${appsSrc}"/icons/*.png; do
          [ -e "$f" ] && install -m644 "$f" "$appdst/icons/$(basename "$f")"
        done

        # ── 10. Walker + Elephant wiring (install/config/walker-elephant.sh) ──
        # Elephant menu providers that power Omarchy's in-launcher Theme,
        # Background-selector and Unlocks menus — symlinked from the runtime tree
        # (the pacman hook from upstream is Arch-only and intentionally dropped).
        oma="$HOME/.local/share/omarchy"
        mkdir -p "$HOME/.config/elephant/menus"
        for m in omarchy_themes omarchy_background_selector omarchy_unlocks; do
          ln -sfn "$oma/default/elephant/$m.lua" "$HOME/.config/elephant/menus/$m.lua"
        done
        # Autostart Walker's gapplication-service (faster SUPER+SPACE) + auto-restart.
        mkdir -p "$HOME/.config/autostart"
        cp -f "$oma/default/walker/walker.desktop" "$HOME/.config/autostart/walker.desktop" 2>/dev/null || true
        chmod u+w "$HOME/.config/autostart/walker.desktop" 2>/dev/null || true
        mkdir -p "$HOME/.config/systemd/user/app-walker@autostart.service.d"
        cp -f "$oma/default/walker/restart.conf" \
              "$HOME/.config/systemd/user/app-walker@autostart.service.d/restart.conf" 2>/dev/null || true
        chmod u+w "$HOME/.config/systemd/user/app-walker@autostart.service.d/restart.conf" 2>/dev/null || true
      fi
    '';
}
