# Omarchy's bundled web apps as proper app-menu launchers (ChatGPT, YouTube,
# WhatsApp, HEY, …). Upstream `install/packaging/webapps.sh` runs
# `omarchy-webapp-install` for each at install time (downloading favicons); we
# generate the same `.desktop` files declaratively. Each launches via
# `omarchy-launch-webapp <url>`, which resolves to the default browser in
# `--app` mode — i.e. Thorium (see omarchy-browsers.nix). Icons come from
# ~/.local/share/applications/icons/ (installed by omarchy-home.nix step 9).
{ config, lib, ... }:

let
  iconDir = "${config.home.homeDirectory}/.local/share/applications/icons";

  # name → url → icon-file (mirrors install/packaging/webapps.sh).
  # HEY and Zoom get protocol-handler Execs + MimeTypes below (upstream
  # registers omarchy-webapp-handler-{hey,zoom} for mailto:/zoommtg:/zoomus:).
  webapps = [
    { n = "HEY";             u = "https://app.hey.com";                              i = "HEY.png";
      x = "omarchy-webapp-handler-hey %u";  m = [ "x-scheme-handler/mailto" ]; }
    { n = "Basecamp";        u = "https://launchpad.37signals.com";                  i = "Basecamp.png"; }
    { n = "WhatsApp";        u = "https://web.whatsapp.com/";                        i = "WhatsApp.png"; }
    { n = "Google Photos";   u = "https://photos.google.com/";                       i = "Google Photos.png"; }
    { n = "Google Contacts"; u = "https://contacts.google.com/";                     i = "Google Contacts.png"; }
    { n = "Google Messages"; u = "https://messages.google.com/web/conversations";    i = "Google Messages.png"; }
    { n = "Google Maps";     u = "https://maps.google.com";                          i = "Google Maps.png"; }
    { n = "ChatGPT";         u = "https://chatgpt.com/";                             i = "ChatGPT.png"; }
    { n = "YouTube";         u = "https://youtube.com/";                             i = "YouTube.png"; }
    { n = "GitHub";          u = "https://github.com/";                              i = "GitHub.png"; }
    { n = "X";               u = "https://x.com/";                                   i = "X.png"; }
    { n = "Figma";           u = "https://figma.com/";                               i = "Figma.png"; }
    { n = "Discord";         u = "https://discord.com/channels/@me";                 i = "Discord.png"; }
    { n = "Zoom";            u = "https://app.zoom.us/wc/home";                       i = "Zoom.png";
      x = "omarchy-webapp-handler-zoom %u";
      m = [ "x-scheme-handler/zoommtg" "x-scheme-handler/zoomus" ]; }
    { n = "Fizzy";           u = "https://app.fizzy.do/";                            i = "Fizzy.png"; }
  ];
in
{
  xdg.desktopEntries =
    # Web apps
    (lib.listToAttrs (map (a: lib.nameValuePair a.n ({
      name = a.n;
      comment = a.n;
      genericName = "Web App";
      exec = a.x or "omarchy-launch-webapp ${a.u}";
      icon = "${iconDir}/${a.i}";
      terminal = false;
      startupNotify = true;
      categories = [ "Network" ];
    } // lib.optionalAttrs (a ? m) { mimeType = a.m; })) webapps))
    # TUI launchers (install/packaging/tuis.sh) — open in a floating/tiled
    # terminal via xdg-terminal-exec with the TUI.float/TUI.tile window classes
    # that Omarchy's hypr window rules target.
    // {
      "Disk Usage" = {
        # The bash command must be DOUBLE-quoted: desktop-file-validate (run by
        # home-manager's makeDesktopItem) errors on a `;` outside double quotes,
        # which would fail the build.
        name = "Disk Usage";
        comment = "Disk usage (dust)";
        exec = ''xdg-terminal-exec --app-id=TUI.float -e bash -c "dust -r; read -n 1 -s"'';
        icon = "${iconDir}/Disk Usage.png";
        terminal = false;
        categories = [ "System" "Utility" ];
      };
      "Docker" = {
        name = "Docker";
        comment = "Docker (lazydocker)";
        exec = "xdg-terminal-exec --app-id=TUI.tile -e lazydocker";
        icon = "${iconDir}/Docker.png";
        terminal = false;
        categories = [ "Development" ];
      };
    };

  # Zoom protocol links resolve to the Zoom webapp handler. NOTE: upstream's
  # mimetypes.sh also points x-scheme-handler/mailto at HEY.desktop; this port
  # deliberately keeps mailto → floorp.desktop (omarchy-browsers.nix) because
  # the user's primary mail flow is browser-based, not HEY. HEY.desktop still
  # advertises the mailto MimeType, so it's one menu click away in any
  # "open with" chooser.
  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/zoommtg" = "Zoom.desktop";
    "x-scheme-handler/zoomus"  = "Zoom.desktop";
  };
}
