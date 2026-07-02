# Day-to-day usage

Operating a running Toonix VM. See [ARCHITECTURE.md](./ARCHITECTURE.md) for how
it's built and [INSTALL.md](../INSTALL.md) for the install procedure.

## Rebuild after editing the config

```sh
sudo nixos-rebuild switch --flake /etc/nixos#toonix
```

(Assumes you placed this repo at `/etc/nixos`; otherwise point `--flake` at
wherever the flake lives, keeping the `#toonix` output name.)

## Validating before you build

The flake exposes a `checks` output (the full system closure), so on any machine
with Nix you can validate without installing:

```sh
nix flake check --no-build   # fast: eval the whole config (catches bad attrs/options)
nix flake check              # full: also builds the system closure
nix fmt                      # format all .nix files (RFC 166 style)
```

`nix develop` drops into a shell with the flake-hacking tools (`just`,
`nixfmt-rfc-style`, `nixd` LSP, `statix`, `deadnix`).

`.github/workflows/check.yml` runs the eval check on every push. A `justfile`
wraps the common commands — `just` to list them, then e.g.:

```sh
just check     # nix flake check
just switch    # rebuild & switch
just vm        # boot this config in a throwaway QEMU VM (nixos-rebuild build-vm)
just update    # bump flake inputs
just gc        # collect garbage + optimise store
```

`just vm` is handy: it builds a runnable VM straight from the flake (no install
needed) so you can smoke-test the desktop quickly.

## Change the theme

Use Omarchy's own tooling — it works on NixOS:

```sh
omarchy-theme-set ristretto      # or: ado, aether, monokai, waffle-cat, demon, …
omarchy-theme-list               # see installed themes
```

…or open the menu (**SUPER + ALT + SPACE**) and pick Theme. The active theme
lives in `~/.config/omarchy/current/`; the installed library is in
`~/.config/omarchy/themes/`. Switches persist across `nixos-rebuild` because the
activation only seeds the active theme when none is set.

## Handy keybindings (Omarchy defaults)

- **SUPER + SPACE** — launch apps (Walker)
- **SUPER + ALT + SPACE** — Omarchy menu
- **SUPER + K** — show all keybindings
- **SUPER + RETURN** — terminal
- **SUPER + CTRL + E** — emoji/symbol picker

## Timezone

Set in `configuration.nix`: `time.timeZone = "America/Chicago";` — change it
there and rebuild.

## Disk, bootloader & swap

Mirrors the host's real Omarchy layout: **Btrfs** root with subvolumes
(`@`→/, `@home`→/home, `@nix`→/nix, `@log`→/var/log, `@snapshots`→/.snapshots,
`compress=zstd`), **GRUB** on UEFI (the menu lists every NixOS generation =
bootable rollback), and **zram** swap (no swap partition). Btrfs auto-scrub and
periodic SSD `fstrim` are enabled; **Snapper** keeps an hourly timeline of `/home`.
The host also LUKS-encrypts root — that's an opt-in here (see the commented
block in `hardware-configuration.nix` and the "Encrypted variant" note in
[INSTALL.md](../INSTALL.md)); the VM defaults to unencrypted so boot needs no
passphrase.

## Enabling NVIDIA

There's a **commented opt-in block** in `configuration.nix` (search for
`NVIDIA (OPT-IN)`). A plain VM only sees an NVIDIA GPU with PCI passthrough/vGPU;
loading the driver without one gives a black screen. Uncomment it **only** if
you're doing GPU passthrough into the VM, then rebuild.

> Heads-up: your captured `~/.config/hypr/hyprland.conf` carries host NVIDIA env
> vars (`LIBVA_DRIVER_NAME=nvidia`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`,
> `NVD_BACKEND=direct`). In a **non-passthrough** VM these are harmless but
> suboptimal — VAAPI / GLX point at an absent driver and fall back to software.
> If you're not passing through an NVIDIA GPU, comment those `env =` lines in
> `hyprland.conf` for clean hardware-accel behavior.

## VM notes

The guest renders on virtio-gpu via software rendering (llvmpipe) — no host GPU
passthrough needed to boot the desktop. SPICE clipboard/auto-resize and the
QEMU guest agent are enabled. For the actual install procedure, see
[INSTALL.md](../INSTALL.md).
