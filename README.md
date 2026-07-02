# Toonix

**Toonix** recreates [Omarchy](https://omarchy.org) **v3.8.2** — DHH's opinionated
Arch + Hyprland setup — declaratively as a **NixOS flake**, for a **QEMU VM**.
Flake output and hostname: `toonix`.

- **Recreates:** Omarchy v3.8.2 (full upstream tree bundled in `omarchy/`)
- **Base:** NixOS `nixos-unstable` + Home-Manager
- **Target:** QEMU/KVM guest — boots on virtio-gpu software rendering, no GPU passthrough
- **Extras:** ristretto theme · **Floorp** (→Firefox) · **Thorium** (→Chromium) · Claude Code preinstalled
- **User:** `bantam`

## Quick start

Boot a throwaway VM straight from the flake — no install needed:

```sh
just vm
```

Install into a QEMU VM — inside the NixOS installer:

```sh
curl -fsSL https://raw.githubusercontent.com/HighRankingBantam/toonix/main/install.sh | sudo bash
```

Validate on any machine with Nix, without installing:

```sh
nix flake check --no-build      # eval the whole system config
```

## Documentation

| Doc | What's in it |
| --- | --- |
| [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) | How it works — the self-mutating-config split, shell, system glue, file-tree |
| [docs/USAGE.md](./docs/USAGE.md) | Day-to-day — rebuild, themes, keybindings, disk/boot, NVIDIA, VM notes |
| [docs/PARITY.md](./docs/PARITY.md) | What works vs. degraded on NixOS, plus Thorium packaging |
| [INSTALL.md](./INSTALL.md) | Full manual VM install |
| [vm/README.md](./vm/README.md) | Local QEMU quick path |

Contributor engineering notes and hard-won gotchas live in
[CLAUDE.md](./CLAUDE.md) / [AGENTS.md](./AGENTS.md).
