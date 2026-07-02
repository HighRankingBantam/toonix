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

      # ── User's own ~/.bashrc additions (captured from the live host) ──────
      # Floorp recreates an empty ~/Floorp dir on every launch; clean it up.
      rmdir ~/Floorp 2>/dev/null
      # Doom Emacs (host install; harmless dead PATH entry when absent)
      export PATH="$HOME/.config/emacs/bin:$PATH"
      # pipx-installed CLIs
      export PATH="$PATH:$HOME/.local/bin"
      [[ -f "$HOME/.config/claw/env" ]] && . "$HOME/.config/claw/env"
      [[ "$TERM_PROGRAM" == "kiro" ]] && . "$(kiro --locate-shell-integration-path bash)"
      # Short alias for Claude Code
      alias cc='claude'
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
