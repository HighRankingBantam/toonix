# Ships the Omarchy v3.8.2 tree into ~/.local/share/omarchy.
#
# Why a symlink to the whole dir instead of individual home.file entries?
#   The omarchy bin scripts use `source` with literal paths like
#   `$OMARCHY_PATH/default/bash/rc` and resolve themselves via `readlink -f`.
#   A single top-level symlink keeps that machinery working without us
#   teaching home-manager about every file.
#
# Executable bits: the Nix store preserves the source file modes, so
# the 282 `omarchy-*` scripts under bin/ remain executable.
{ ... }:

{
  # Mount the read-only Nix-store copy of the tree at the canonical path.
  home.file.".local/share/omarchy" = {
    source = ../omarchy;
    recursive = false;       # Single symlink to the top-level dir
  };
}
