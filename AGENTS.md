# AGENTS.md — Toonix

Toonix is a **NixOS flake** (output/host `toonix`) that recreates the user's
**Omarchy v3.8.2** Hyprland desktop declaratively, to run in a **QEMU VM**.

**`CLAUDE.md` is the authority — read it first.** It documents the architecture
(how the self-mutating Omarchy userland is shipped *writable* into `$HOME`), the
`omarchy-*` commands that are deliberately stubbed on NixOS, and ~13 hard-won
gotchas. Each gotcha exists because it already broke an eval once — check them
before "fixing" something that looks odd.

## Non-negotiable invariants

- **Omarchy v3.8.2** (`.conf`-based). Never pull `main`/v4.x (Lua, different layout).
- **Target = QEMU VM.** NVIDIA is an opt-in commented block; enabling it black-screens the VM.
- **Active theme = `ristretto`** (seed in `user-configs/omarchy-current/`).
- **Boot = GRUB/UEFI · root = btrfs subvolumes · swap = zram** (see `configuration.nix`).

## Validate (no full build needed to catch config errors)

- `nix flake check --no-build` — evaluates the whole system closure; catches
  option/attribute/type errors. **This is the fast correctness gate.**
- `nix flake check` — also builds the closure. `nix fmt` formats (RFC 166).
- `just` — lists VM/build/switch helpers. Full boot test = install into the
  QEMU VM (`vm/README.md`, `INSTALL.md`).

## Working here

- Match existing style; keep changes scoped to what was asked.
- The bundled `omarchy/` tree is **vendored upstream** (read-only source) — its
  own conventions live in `omarchy/AGENTS.md`; don't add Toonix notes there.
