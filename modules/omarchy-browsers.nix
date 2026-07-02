# Browsers: Floorp (replaces Firefox) + Thorium (replaces Chromium).
#
# Floorp is `pkgs.floorp-bin` (the plain `floorp` attr was removed in 2025 —
# upstream stopped being buildable from source, so nixpkgs ships the binary).
#
# Thorium (Alex313031's Chromium fork) is NOT in nixpkgs (`thorium-reader` is an
# unrelated ebook app). We package the official AppImage with appimageTools.
# Omarchy is chromium-keyed everywhere (omarchy-launch-webapp falls back to
# `chromium.desktop`), so we ship a `chromium.desktop` that launches Thorium —
# that makes web apps (SUPER+SHIFT+A/Y/…) and the browser bindings resolve to
# Thorium with no script patching.
{ config, pkgs, lib, ... }:

let
  # Thorium isn't in nixpkgs → fetch the official AppImage. version + both hashes
  # are REAL (release M138.0.7204.303, computed from the actual ~282 MB assets),
  # so this builds as-is with no manual step.
  #
  # cpuVariant defaults to SSE3 because the DEFAULT QEMU CPU model (`qemu64`) does
  # NOT expose SSE4.1/4.2 — an SSE4/AVX2 Thorium would SIGILL on it. SSE3 runs on
  # any x86-64. If you boot QEMU with `-cpu host` (or run on real hardware) and
  # want the faster build, set cpuVariant = "SSE4" (hash already provided).
  # To bump the version: update thoriumVersion + refresh the hashes
  # (`nix-prefetch-url <url>` for each variant you use; see `just thorium-hash`).
  thoriumVersion = "138.0.7204.303";
  cpuVariant = "SSE3"; # "SSE3" = safe on bare qemu64 | "SSE4" = faster, needs -cpu host
  thoriumHashes = {
    SSE3 = "sha256-GeMbA+8D/Mah6qhLpv8Y4ONzpaxg3xJWVizzMOlilLc=";
    SSE4 = "sha256-g8C/RT3O++4GLb09RahLCB+3RuSE/EfICf9iIAkRccA=";
    AVX2 = "sha256-sXzUgqZ9loprBCObHXLRjkW15EzFFMBbqqqxuQ+ZIjA=";
  };
  thoriumSrc = pkgs.fetchurl {
    url = "https://github.com/Alex313031/thorium/releases/download/M${thoriumVersion}/Thorium_Browser_${thoriumVersion}_${cpuVariant}.AppImage";
    hash = thoriumHashes.${cpuVariant};
  };

  thoriumAppImage = pkgs.appimageTools.wrapType2 {
    pname = "thorium-browser-unwrapped";
    version = thoriumVersion;
    src = thoriumSrc;
    # Wayland/ozone runtime libs the Chromium AppImage may dlopen.
    extraPkgs = p: with p; [ libGL libxkbcommon ];
  };

  # Chromium forks do NOT read a flags file natively — on Arch that's done by
  # the distro launcher script. Recreate that here so thorium-flags.conf
  # (ozone/Wayland + the Copy-URL extension below) actually takes effect.
  # The wrapper keeps the `thorium-browser` name, so the .desktop Execs and
  # omarchy-launch-webapp's first-token extraction keep working.
  thorium = pkgs.writeShellScriptBin "thorium-browser" ''
    flags=()
    if [ -f "$HOME/.config/thorium/thorium-flags.conf" ]; then
      while IFS= read -r line; do
        case "$line" in ""|\#*) continue ;; esac
        flags+=("$line")
      done < "$HOME/.config/thorium/thorium-flags.conf"
    fi
    exec ${thoriumAppImage}/bin/thorium-browser-unwrapped "''${flags[@]}" "$@"
  '';
in
{
  # Browser binaries (on PATH for the session). NOTE: with
  # home-manager.useUserPackages=true these install under
  # /etc/profiles/per-user/bantam, NOT ~/.nix-profile — so we do NOT rely on the
  # packages' own .desktop files being found by omarchy's launchers. Instead the
  # explicit xdg.desktopEntries below put thorium-browser.desktop/chromium.desktop
  # in ~/.local/share/applications (which the launchers DO grep) and exec the
  # binary by name (which is on PATH). That's what makes the launchers resolve.
  home.packages = [
    # Floorp with Omarchy's Firefox policies (default/firefox/policies.json) —
    # VAAPI/HW video decode + Wayland fractional scaling, all user-overridable.
    (pkgs.floorp-bin.override {
      extraPolicies.Preferences = {
        "apz.overscroll.enabled"                        = { Value = true;  Status = "default"; };
        "media.ffmpeg.vaapi.enabled"                    = { Value = true;  Status = "default"; };
        "media.hardware-video-decoding.force-enabled"   = { Value = true;  Status = "default"; };
        "widget.disable-swipe-tracker"                  = { Value = false; Status = "default"; };
        "widget.wayland.fractional-scale.enabled"       = { Value = true;  Status = "default"; };
      };
    })
    thorium
  ];

  # Desktop entries with KNOWN names (don't rely on what the AppImage ships).
  # Both Exec start with `thorium-browser`, which is what the omarchy launchers
  # extract and run (with --app=<url> for web apps).
  xdg.desktopEntries.thorium-browser = {
    name = "Thorium";
    genericName = "Web Browser";
    exec = "thorium-browser %U";
    icon = "thorium-browser";
    terminal = false;
    categories = [ "Network" "WebBrowser" ];
    mimeType = [
      "text/html" "x-scheme-handler/http" "x-scheme-handler/https"
      "x-scheme-handler/about" "x-scheme-handler/unknown"
    ];
  };
  # Alias so Omarchy's hardcoded `chromium.desktop` fallback launches Thorium.
  xdg.desktopEntries.chromium = {
    name = "Chromium (→ Thorium)";
    genericName = "Web Browser";
    exec = "thorium-browser %U";
    icon = "thorium-browser";
    terminal = false;
    categories = [ "Network" "WebBrowser" ];
    mimeType = [ "text/html" "x-scheme-handler/http" "x-scheme-handler/https" ];
  };

  # Default browser → Thorium (merges with the non-browser handlers in
  # omarchy-home-extras.nix; xdg.mimeApps.enable is set there).
  xdg.mimeApps.defaultApplications = {
    "text/html"               = "thorium-browser.desktop";
    "x-scheme-handler/http"   = "thorium-browser.desktop";
    "x-scheme-handler/https"  = "thorium-browser.desktop";
    "x-scheme-handler/about"  = "thorium-browser.desktop";
    "x-scheme-handler/chat"   = "thorium-browser.desktop";
    "x-scheme-handler/mailto" = "floorp.desktop";
  };

  # Thorium flags (Chromium-style flags file it reads on launch). Mirrors
  # Omarchy's config/chromium-flags.conf — Wayland/ozone + touchpad overscroll
  # + the bundled "Copy URL" extension (Alt+Shift+L), loaded by absolute path
  # from the read-only omarchy runtime tree.
  xdg.configFile."thorium/thorium-flags.conf".text = ''
    --ozone-platform-hint=auto
    --ozone-platform=wayland
    --enable-features=UseOzonePlatform,WaylandWindowDecorations,TouchpadOverscrollHistoryNavigation
    --gtk-version=4
    --load-extension=${config.home.homeDirectory}/.local/share/omarchy/default/chromium/extensions/copy-url
  '';

  # Seed Omarchy's chromium profile defaults (dark color scheme) into Thorium's
  # profile, only if the profile doesn't exist yet — the browser rewrites
  # Preferences constantly, so this must never clobber a live profile.
  home.activation.thoriumProfileSeed =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -z "''${DRY_RUN_CMD:-}" ]; then
        prefs="$HOME/.config/thorium/Default/Preferences"
        if [ ! -e "$prefs" ]; then
          mkdir -p "$HOME/.config/thorium/Default"
          install -m644 ${../omarchy/config/chromium/Default/Preferences} "$prefs"
        fi
      fi
    '';
}
