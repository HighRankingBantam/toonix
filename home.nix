# Home-Manager entry point — wires up the Omarchy runtime + config tree
# and applies the user's actual customizations.
{ config, ... }:

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
  # `omarchy-swayosd-client`, which talks to this server. There is no NixOS
  # `services.swayosd`, so we run the server via Home-Manager (the upstream
  # user unit hardcodes /usr/bin/swayosd-server and won't work on NixOS).
  services.swayosd.enable = true;

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
    userName  = "bantam";
    userEmail = "nla.0105@proton.me";
    aliases = { co = "checkout"; br = "branch"; ci = "commit"; st = "status"; };
    extraConfig = {
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
