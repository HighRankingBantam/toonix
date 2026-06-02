# Bash setup — mirrors Omarchy's default ~/.bashrc, which simply sources the
# Omarchy bash framework (envs, aliases, functions, starship/zoxide/mise init).
{ ... }:

{
  programs.bash = {
    enable = true;

    # Omarchy's bash/rc bundles: envs, shell opts, aliases (ls→eza, cd→zoxide,
    # g=git, n=nvim, c=opencode, lazygit…), fns, and init (starship + zoxide +
    # mise eval). Those binaries are installed system-wide, so sourcing works.
    initExtra = ''
      if [ -r "$HOME/.local/share/omarchy/default/bash/rc" ]; then
        source "$HOME/.local/share/omarchy/default/bash/rc"
      fi

      # NixOS-compat: make the Arch-only-command stubs (omarchy-nixos-compat.nix)
      # win PATH. This MUST run after Omarchy's bash/rc, which re-prepends its own
      # $OMARCHY_PATH/bin. Harmless no-op if the override dir doesn't exist.
      case ":$PATH:" in
        *":$HOME/.local/share/omarchy-nixos-overrides:"*) ;;
        *) export PATH="$HOME/.local/share/omarchy-nixos-overrides:$PATH" ;;
      esac
    '';
  };

  # Omarchy's bash/init looks for fzf integration under /usr/share/fzf/* which
  # doesn't exist on NixOS — so wire fzf's bash integration the Nix way.
  # (starship/zoxide/mise are eval-initialized by Omarchy's bash/init and work
  # fine on NixOS, so we deliberately don't double-init them here.)
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
  };
}
