# Helper commands for the Omarchy-on-NixOS flake. Run `just <recipe>`.
# (Install `just` via `nix shell nixpkgs#just` or it's in the system once built.)

flake := "/etc/nixos"
host  := "toonix"

# List recipes
default:
    @just --list

# Rebuild & switch to this config (run on the installed VM)
switch:
    sudo nixos-rebuild switch --flake {{flake}}#{{host}}

# Build & activate without adding a boot entry (safe trial)
test:
    sudo nixos-rebuild test --flake {{flake}}#{{host}}

# Build only — no activation (catches eval/build errors)
build:
    nixos-rebuild build --flake {{flake}}#{{host}}

# Full eval+build of the system closure via the flake `checks` output.
# This is the real validation that couldn't be run while authoring.
check:
    nix flake check --print-build-logs

# Boot this config in a throwaway QEMU VM straight from the flake (great for
# testing without a full install; creates a ./toonix.qcow2 disk image).
vm:
    nixos-rebuild build-vm --flake {{flake}}#{{host}}
    @echo "Run ./result/bin/run-{{host}}-vm to start the VM."

# Update flake inputs (nixpkgs + home-manager) and show the diff
update:
    nix flake update
    @echo "Review flake.lock changes, then: just switch"

# Format all .nix files (RFC 166 style)
fmt:
    nix fmt

# Garbage-collect old generations (>14d) and optimise the store
gc:
    sudo nix-collect-garbage --delete-older-than 14d
    sudo nix-store --optimise

# Show the current Omarchy theme + how to switch it
theme:
    @echo "Active theme: $(cat ~/.config/omarchy/current/theme.name 2>/dev/null || echo '?')"
    @echo "Switch with: omarchy-theme-set <name>   (list: omarchy-theme-list)"

# Refresh the Thorium pin for a given version (+ optional CPU variant, default SSE3)
thorium-hash version variant="SSE3":
    @echo "nix-prefetch-url 'https://github.com/Alex313031/thorium/releases/download/M{{version}}/Thorium_Browser_{{version}}_{{variant}}.AppImage'"
    @echo "That prints a base32 hash; convert with: nix hash to-sri --type sha256 <hash>"
    @echo "Then update thoriumVersion / thoriumHashes.{{variant}} in modules/omarchy-browsers.nix"
