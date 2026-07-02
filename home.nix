# Home-Manager entry point — wires up the Omarchy runtime + config tree
# and applies the user's actual customizations.
{ config, pkgs, ... }:

{
  imports = [
    ./modules/omarchy-runtime.nix       # Ships omarchy/ → ~/.local/share/omarchy (read-only store symlink)
    ./modules/omarchy-home.nix          # Installs configs + state into $HOME, WRITABLE (mirrors Omarchy's installer)
    ./modules/omarchy-home-extras.nix   # Mimetypes, XDG user-dirs, .XCompose, WirePlumber drop-ins, ~/Work
    ./modules/omarchy-browsers.nix      # Floorp (replaces Firefox) + Thorium (replaces Chromium) + default-browser wiring
    ./modules/omarchy-webapps.nix       # Web-app launchers (ChatGPT, YouTube, WhatsApp, HEY, …) via omarchy-launch-webapp
    ./modules/omarchy-nixos-compat.nix  # Neutralizes Arch-only omarchy commands (pacman/boot writes)
    ./modules/shell.nix                 # Bash + sources omarchy's bash defaults
  ];

  # SwayOSD volume/brightness overlay. Omarchy's media keybindings call
  # `omarchy-swayosd-client`, which talks to this server. The upstream user
  # unit hardcodes /usr/bin/swayosd-server, so we ship our own — but the unit
  # name MUST stay `swayosd-server` (upstream's name): omarchy-restart-swayosd
  # runs `systemctl --user enable --now swayosd-server.service` on every theme
  # switch, and HM's `services.swayosd` names its unit `swayosd.service`
  # (VM-verified: "Unit swayosd-server.service does not exist" → the OSD kept
  # the old theme). Mirrors omarchy/config/systemd/user/swayosd-server.service.
  systemd.user.services.swayosd-server = {
    Unit = {
      Description = "SwayOSD server";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.swayosd}/bin/swayosd-server";
      Restart = "always";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  home.username = "bantam";
  home.homeDirectory = "/home/bantam";
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;

  # Session env — duplicates ~/.config/uwsm/env so non-graphical shells
  # (TTY/SSH) also get the Omarchy bin path.
  home.sessionVariables = {
    OMARCHY_PATH = "${config.home.homeDirectory}/.local/share/omarchy";
    EDITOR = "nvim";
    TERMINAL = "xdg-terminal-exec";
    BROWSER = "thorium-browser";
  };

  home.sessionPath = [
    "$HOME/.local/share/omarchy/bin"
    "$HOME/.local/bin"
  ];

  # XDG base enable. user-dirs + mimetype defaults live in omarchy-home-extras.nix;
  # browser/mailto defaults live in omarchy-browsers.nix.
  xdg.enable = true;

  # Git: identity + Omarchy's shipped git config (omarchy/config/git/config).
  programs.git = {
    enable = true;
    # home-manager renamed userName/userEmail/aliases/extraConfig → settings.*
    # (freeform git config) on current unstable; CI warnings confirmed the paths.
    settings = {
      user = { name = "bantam"; email = "nla.0105@proton.me"; };
      alias = { co = "checkout"; br = "branch"; ci = "commit"; st = "status"; };
      init.defaultBranch = "master";          # Omarchy's default
      pull.rebase = true;
      push.autoSetupRemote = true;
      diff = { algorithm = "histogram"; colorMoved = "plain"; mnemonicPrefix = true; };
      commit.verbose = true;
      column.ui = "auto";
      branch.sort = "-committerdate";
      tag.sort = "-version:refname";
      rerere = { enabled = true; autoupdate = true; };
    };
  };
}
