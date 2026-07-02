# Architecture

How Toonix reproduces Omarchy on NixOS. See [USAGE.md](./USAGE.md) for day-to-day
operation and [PARITY.md](./PARITY.md) for the feature-by-feature status.

## What this is

Omarchy is normally an Arch installer that pulls packages with `pacman`/`yay`,
copies a tree of dotfiles into `~/.config`, and wires up Hyprland, Waybar,
Walker, theming, and ~282 `omarchy-*` helper scripts. This repo reproduces the
*result* on NixOS:

- **Packages** come from `nixpkgs` (declared in `configuration.nix`), not pacman.
- **Boot, display manager, audio, fonts, services** are configured the NixOS way.
- **The Omarchy userland** (the upstream `omarchy/` tree and all its configs,
  scripts, themes, and bash framework) is shipped into `$HOME` so the desktop
  behaves like real Omarchy — theme switching, the menu, toggles, and keybindings
  all work.

The session is **SDDM → Hyprland under UWSM** (`programs.hyprland.withUWSM = true`),
which is what Omarchy's bindings expect (every binding calls `uwsm-app --`).

## How it works

The tricky part is that **Omarchy is self-mutating**: theme switches do
`rm -rf current/ && mv …`, toggles write into `~/.local/state/omarchy/`, and
menus rewrite files under `~/.config` at runtime. That rules out the usual
Nix approach of symlinking config files read-only out of the store. So the repo
splits the job in two:

### 1. `omarchy/` → `~/.local/share/omarchy` (read-only, the "source")

`modules/omarchy-runtime.nix` places **one symlink** from
`~/.local/share/omarchy` to the bundled `omarchy/` tree in the Nix store. This is
the canonical Omarchy install path. The 282 `bin/omarchy-*` scripts resolve
themselves and `source` files relative to this path (e.g.
`$OMARCHY_PATH/default/bash/rc`), so a single top-level symlink keeps all that
machinery working. Executable bits are preserved by the store. This directory is
**read-only** — it's the pristine upstream code, never mutated.

### 2. Omarchy's configs → `~/.config` (writable, the "working copy")

`modules/omarchy-home.nix` is a **Home-Manager activation script** (not
`home.file` symlinks). On every `nixos-rebuild`/activation it mirrors exactly
what Omarchy's real installer does. Upstream `install/config/config.sh` runs:

```sh
cp -R ~/.local/share/omarchy/config/* ~/.config/
```

The activation reproduces that with `cp -Rf` + `chmod u+w`, so every app config
lands in `~/.config` as a **writable, Omarchy-owned** file. Specifically it:

1. **Copies stock per-app configs** from `omarchy/config/*` into `~/.config/`
   (alacritty, waybar, btop, foot, ghostty, kitty, fastfetch, swayosd, etc.),
   skipping a few dirs it handles specially (`omarchy`, `git`, `chromium`, and
   the four the user overrides).
2. **Overlays the user's real customizations** on top: `user-configs/hypr`,
   `user-configs/uwsm`, `user-configs/walker`, `user-configs/alacritty`.
3. **Seeds `~/.config/omarchy/`** runtime dir (themed/, extensions/, hooks/),
   including the user's `theme-set` hook and `post-boot.d`.
4. **Seeds the installed theme library** (`user-configs/omarchy-themes`, ~229 MB:
   ado, aether, all-hallows-eve, arc-blueberry, demon, monokai, waffle-cat) into
   `~/.config/omarchy/themes/` — **only if absent**, so a theme you install in
   the VM survives a rebuild.
5. **Seeds the active theme = ristretto** into `~/.config/omarchy/current/`
   (rendered theme + `theme.name`), and points `current/background` at the
   theme's launch wallpaper — **only if no theme is set yet**, so switching
   themes inside the VM survives `nixos-rebuild`.
6. **Creates Omarchy's theme-managed symlinks** (mirroring `install/config/theme.sh`):
   `~/.config/btop/themes/current.theme` and `~/.config/mako/config` both point
   into `current/theme/`.
7. **Pre-marks every migration** (`touch`-es all 325 `omarchy/migrations/*.sh`
   into `~/.local/state/omarchy/migrations/`) so a stray `omarchy update` never
   tries to replay an Arch-only pacman/sudo migration; also creates the
   `~/.local/state/omarchy/toggles/hypr` state dir.
8. **Installs Omarchy's custom Waybar glyph font** (`omarchy.ttf`) into
   `~/.local/share/fonts` and refreshes the font cache.

**Why activation-copy instead of read-only Nix symlinks?** Because Omarchy
rewrites `~/.config` at runtime (theme switching, toggles, the menu). Read-only
store symlinks would make all of that fail with permission errors. Copying the
config every rebuild keeps the stock files reproducible while leaving runtime
state (current theme, theme library, toggle flags) seeded *only-if-absent* so
rebuilds never clobber in-VM changes.

> Note on symlinks: the activation copies with `cp -Rf` (not `-L`). Omarchy's
> `hypr/shaders/` link into `/usr/share/aether` (an AUR package with no nixpkgs
> build), so those links dangle here; preserving them as-is is harmless since
> Hyprland only reads a shader when one is toggled on.

### 3. Shell

`modules/shell.nix` enables bash and sources Omarchy's bash framework
(`~/.local/share/omarchy/default/bash/rc` → envs, aliases like `ls→eza`,
`cd→zoxide`, `g=git`, `n=nvim`, plus starship/zoxide/mise init). fzf's bash
integration is wired the Nix way (Omarchy's init expects `/usr/share/fzf/*`).

### 4. System glue worth knowing

- **Polkit agent path hack:** Omarchy's autostart starts the polkit agent via a
  hardcoded Arch path `/usr/lib/polkit-gnome/...`. `configuration.nix` materializes
  exactly that path as a `systemd.tmpfiles` symlink to the nixpkgs binary, so
  Omarchy's unmodified autostart works.
- **VM rendering:** `WLR_RENDERER_ALLOW_SOFTWARE=1` + `WLR_NO_HARDWARE_CURSORS=1`
  and an early `virtio_gpu` module let wlroots/Hyprland start on llvmpipe inside
  QEMU without 3D/virgl.

## File-tree overview

```text
nixos/
├── flake.nix                       # Flake: nixosConfigurations.toonix + Home-Manager; `checks` (nix flake check) + `formatter` (nix fmt)
├── configuration.nix               # NixOS system: GRUB, btrfs, zram, snapper, SDDM+Hyprland/UWSM, audio, fonts, packages
│                                   #   imports → system-tweaks.nix + omarchy-branding.nix
├── hardware-configuration.nix      # Btrfs-subvolume TEMPLATE (+ opt-in LUKS) — replace w/ nixos-generate-config output at install
├── home.nix                        # Home-Manager entry: imports the 7 home modules, git identity, session env, swayosd
├── justfile                        # `just` helpers: switch/test/build/check/vm/update/gc/fmt
├── .github/workflows/check.yml     # CI: `nix flake check` on push
├── .gitignore
│
├── modules/
│   │  # — system modules (imported by configuration.nix) —
│   ├── system-tweaks.nix           # Omarchy install/config/* tweaks: sysctls, fd-limits, fast-shutdown, sudo, wifi, locate, gpg, fuse-sleep
│   ├── omarchy-branding.nix        # SDDM greeter theme + Plymouth boot splash (packaged from omarchy/)
│   │  # — home-manager modules (imported by home.nix) —
│   ├── omarchy-runtime.nix         # Symlinks omarchy/ → ~/.local/share/omarchy (read-only source)
│   ├── omarchy-home.nix            # Activation: installs configs+state into $HOME as WRITABLE (mirrors installer)
│   ├── omarchy-home-extras.nix     # Mimetypes, XDG user-dirs, .XCompose, WirePlumber drop-ins, ~/Work mise
│   ├── omarchy-browsers.nix        # Floorp (→Firefox) + Thorium (→Chromium) + default-browser/webapp wiring
│   ├── omarchy-webapps.nix         # Web apps + TUI launchers (ChatGPT/YouTube/… → Thorium --app; dust/lazydocker/btop)
│   ├── omarchy-nixos-compat.nix    # Stubs Arch-only commands (omarchy update / refresh-* / pkg-*) so they no-op
│   └── shell.nix                   # Bash sources Omarchy's bash framework; fzf integration; compat PATH-win
│
├── omarchy/                        # Bundled upstream Omarchy v3.8.2 tree (read-only)
│   ├── bin/                        # 282 omarchy-* helper scripts (menu, theme, launch, toggle, …)
│   ├── config/                     # Stock per-app dotfiles → copied into ~/.config
│   ├── default/                    # Omarchy defaults: bash framework, default hypr/waybar/walker, themed/
│   ├── themes/                     # Built-in themes shipped with Omarchy
│   ├── migrations/                 # 325 Arch migration scripts (pre-marked done; never run on NixOS)
│   ├── install/                    # Upstream Arch installer (reference only — NOT executed on NixOS)
│   └── version                     # "3.8.2"
│
└── user-configs/                   # The user's real customizations + rendered active theme
    ├── hypr/                       # Real Hyprland config (bindings.conf, monitors, looknfeel, shaders, …)
    ├── uwsm/                       # UWSM env/default (adds Omarchy bin to PATH, sources defaults)
    ├── walker/                     # Walker launcher config.toml (providers, prefixes, theme)
    ├── alacritty/                  # User alacritty.toml
    ├── mako/                       # User mako overrides
    ├── omarchy-current/            # Rendered "ristretto" theme seed (theme/ + theme.name)
    ├── omarchy-hooks/              # theme-set hook + post-boot.d + samples
    └── omarchy-themes/             # Installed alt-theme library (~229 MB; seeded once)
```
