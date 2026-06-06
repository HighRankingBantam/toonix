# Toonix

**Toonix** is [Omarchy](https://omarchy.org) — DHH's opinionated Arch + Hyprland
setup, **v3.8.2** — recreated declaratively as a NixOS flake, for a **QEMU VM**.
(The flake output and hostname are `toonix`.)

- **Distro recreated:** Omarchy v3.8.2 (the full upstream tree is bundled in `omarchy/`)
- **Base OS:** NixOS (`nixos-unstable`), managed by a flake + Home-Manager
- **Target:** a QEMU/KVM guest (boots on virtio-gpu with software rendering — no GPU passthrough required)
- **Extras:** **Claude Code** preinstalled; active theme is **ristretto**;
  **Floorp** (instead of Firefox) and **Thorium** (instead of Chromium) browsers
- **Flake output:** `toonix` (i.e. `.#toonix`)
- **User:** `bantam`

For the quick local QEMU path, start with [vm/README.md](./vm/README.md). Inside
the NixOS installer VM, the internet install path is:

```sh
curl -fsSL https://raw.githubusercontent.com/HighRankingBantam/toonix/main/install.sh | sudo bash
```

For the fully manual VM install, see [INSTALL.md](./INSTALL.md).

---

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

---

## Architecture — how it works

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

---

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

---

## What works / what's degraded on NixOS

| Area | Status | Notes |
| --- | --- | --- |
| Hyprland desktop (UWSM session) | Works | SDDM → "Hyprland (UWSM)"; software-rendered in the VM |
| Waybar | Works | Including Omarchy's custom glyph font |
| Theme switching | Works | `omarchy-theme-set` / the theme menu; ristretto active by default. Note: your captured `~/.config/omarchy/hooks/theme-set` syncs a **Zen browser** theme (from before the Floorp switch) — it no-ops gracefully (a harmless "no Zen profile" toast) and doesn't block the switch; delete that hook if you don't want the toast |
| Most keybindings | Works | Terminal, browser, file manager, menu, screenshots, media keys, etc. |
| Screen lock / idle | Works | `programs.hyprlock.enable` sets up the PAM service so hyprlock can actually **unlock** (idle-lock via hypridle + SUPER+CTRL+L). Without that PAM entry you'd be locked out — it's wired |
| Walker launcher | Works | `elephant` (its data provider) packaged and enabled as a user service so `omarchy-restart-walker` restarts it; Walker itself is autostarted via `~/.config/autostart` + auto-restart drop-in. Omarchy's in-launcher **Theme / Background / Unlocks menus** wired (elephant menu providers symlinked into `~/.config/elephant/menus/`, `omarchy-home.nix` step 10) |
| SDDM + Plymouth themes | Works | Omarchy's greeter + boot splash packaged from `omarchy/` (`modules/omarchy-branding.nix`) |
| System tweaks | Works | Ported from Omarchy `install/config/*`: inotify watchers, fd limits, fast shutdown, sudo tries=10, passwordless timezone picker, wifi powersave off, wireless regulatory domain/database, power button ignored for Omarchy's power menu, USB autosuspend disabled, locate/plocate, GPG keyservers, fuse-unmount-before-sleep (`modules/system-tweaks.nix`) |
| Networking / Docker firewall | Works | NetworkManager uses Omarchy's iwd Wi-Fi backend; Omarchy's resolved stub, Docker bridge DNS listener, socket-activated Docker daemon with bounded JSON logs, and LocalSend TCP/UDP 53317 firewall allowance are declared in `configuration.nix` |
| Printer discovery | Works | CUPS + Avahi are enabled, `.local` mDNS resolution is handled through Avahi, resolved mDNS is disabled, `cups-browsed` auto-creates remote printers (`CreateRemotePrinters Yes`), CUPS-PDF is installed, and `system-config-printer` is enabled |
| Firmware / Thunderbolt | Works | `services.fwupd` and `services.hardware.bolt` are enabled. `omarchy-update-firmware` is shadowed with a NixOS-safe `fwupdmgr` flow instead of copying EFI payloads into Arch paths |
| Package parity | Improved | Added more direct mappings from `omarchy/install/omarchy-base.packages`: Docker compose/buildx, FAT/exFAT tools, ALSA utilities, `less`, `qalc` (`libqalculate`), `tree-sitter`, `usage`, DB client libraries (`libpq`/MariaDB connector), Typora, 1Password GUI/CLI, WebP pixbuf support, MTP/NFS helpers, and `tzupdate` |
| Mimetypes / XDG dirs / XCompose | Works | Omarchy's imv·mpv·evince·nvim defaults, disabled Templates/Public/Desktop, writable GTK/Nautilus bookmarks, and CapsLock-compose emoji (`modules/omarchy-home-extras.nix`) |
| GNOME/GTK defaults + keyring | Works | Omarchy first-run defaults are declarative: dark GTK/color scheme, ristretto's Yaru-yellow icons, primary-paste enabled, and passwordless `Default_keyring` seeded only if absent (`modules/omarchy-home-extras.nix`) |
| Omarchy assistant skill | Works | `install/config/omarchy-ai-skill.sh` is ported: the bundled Omarchy skill is symlinked into `~/.agents`, `~/.claude`, `~/.codex`, and `~/.pi/agent` skill directories |
| App-menu launchers + declutter | Works | Omarchy's Alacritty/imv/mpv/typora launchers + 34 `Hidden=true` entries (avahi-discover, java/fcitx config tools, electron stubs…) + webapp icons, installed to `~/.local/share/applications` (`omarchy-home.nix` step 9) |
| Web apps | Works | All 15 (ChatGPT, YouTube, WhatsApp, HEY, GitHub, X, Figma, Discord, Zoom, Google {Photos,Maps,Messages,Contacts}, Basecamp, Fizzy) generated as `.desktop` launchers that open as Thorium `--app` windows (`modules/omarchy-webapps.nix`); copy-url extension (Alt+Shift+L) wired into Thorium |
| TUI launchers | Works | Disk Usage (dust) + Docker (lazydocker) open in floating/tiled terminals via `xdg-terminal-exec` (`omarchy-webapps.nix`) |
| Terminal selection | Works | `omarchy-install-terminal` is shadowed with a NixOS-safe implementation that selects among the already-declared terminals instead of invoking pacman |
| Dictation / Voxtype | Partial | `pkgs.voxtype` is declared and a writable config is seeded. `omarchy-voxtype-install` is shadowed to download the model and enable the user service without pacman; model download remains opt-in |
| Branding / toggles | Works | fastfetch logo (`branding/about.txt`) + screensaver text + `~/.local/state/omarchy/toggles/hypr/flags.conf` all seeded (`omarchy-home.nix` steps 3 & 7) |
| Browsers | Works | **Floorp** (`floorp-bin`, with Omarchy's Firefox VAAPI/Wayland policies applied) replaces Firefox; **Thorium** replaces Chromium and is the default — web apps resolve to it via a `chromium.desktop`→Thorium alias. Thorium isn't in nixpkgs so it's packaged from the official AppImage, pinned to a real release+hash — **builds as-is, no manual step** (see the note below to pick the CPU variant / bump the version) |
| Git config | Works | Omarchy's `config/git/config` ported into `programs.git` (aliases co/br/ci/st, rerere, histogram diff, push.autoSetupRemote, …) |
| Screen recording | Works | `programs.gpu-screen-recorder.enable` installs Omarchy's recorder and the setcap wrapper it needs; `wl-screenrec` is also installed as a fallback. Screenshots/OCR use grim/slurp/satty/tesseract |
| Debug / hardware helpers | Works | `omarchy-debug` is shadowed with a NixOS report instead of pacman/expac output; `omarchy-hw-vulkan` checks NixOS OpenGL/Vulkan driver paths plus `vulkaninfo` |
| Claude Code | Works | Preinstalled via `pkgs.claude-code`; Omarchy's `cx` alias launches `claude` |
| `omarchy update` / package installers | Blocked safely | Updates and install/remove/package workflows pull from pacman/AUR + git on Arch. Toonix shadows them with clear NixOS messages; edit `/etc/nixos` and run `sudo nixos-rebuild switch --flake /etc/nixos#toonix` instead |
| `omarchy-refresh-{pacman,sddm,plymouth,limine}` | Do NOT run | Arch/boot-specific; NixOS owns packages, SDDM, Plymouth, and the bootloader declaratively |
| `omarchy-toggle-hybrid-gpu` | Do NOT run | Arch GPU-driver toggling; configure GPUs in `configuration.nix` instead |
| Keyboard RGB theming | No-op | `omarchy-theme-set-keyboard*` targets ASUS ROG / Framework 16 hardware; harmless no-op in a VM |
| AUR-only apps | Omitted | e.g. aether, cliamp, omarchy-nvim — see the omitted list in `configuration.nix` |
| Nautilus right-click extensions | Works | Omarchy's `localsend.py`/`transcode.py` installed via `pkgs.nautilus-python` + the `.py` in `~/.local/share/nautilus-python/extensions/`, with `NAUTILUS_4_EXTENSION_DIR` pointed at the loader so Nautilus actually loads them ("Send via LocalSend"/"Transcode" right-click items). They also no-op gracefully if a helper binary is missing |

> Rule of thumb: anything that mutates **packages, the bootloader, SDDM,
> Plymouth, or system migrations** is the wrong tool on NixOS — those are
> declared in `configuration.nix` and applied with `nixos-rebuild`. Anything
> that only touches **`~/.config` / `~/.local/state`** (themes, toggles, the
> menu, launchers) behaves like real Omarchy.

### Thorium (packaged from the official AppImage)

The Thorium browser fork is **not in nixpkgs** (the packaging request was closed;
`thorium-reader` is an unrelated ebook app), so `modules/omarchy-browsers.nix`
builds it from the official upstream **AppImage** via `appimageTools`. It's
**pinned to a real release + hash** (`M138.0.7204.303`), so it **builds as-is —
no manual step**.

**CPU variant matters in a VM.** It defaults to **`cpuVariant = "SSE3"`** because
the default QEMU CPU model (`qemu64`) does *not* expose SSE4.1/4.2 — an SSE4/AVX2
build would crash with an illegal instruction. SSE3 runs everywhere. If you boot
QEMU with `-cpu host` (or run on real hardware) and want the faster build, set
`cpuVariant = "SSE4"` in the module — both hashes are already baked in, so it's a
one-word change.

To bump the version: update `thoriumVersion`, then refresh the hash(es) with
`nix-prefetch-url <url>` (`just thorium-hash <version>` prints the command).
Floorp needs none of this — `pkgs.floorp-bin` is in nixpkgs.

---

## Day-to-day

### Rebuild after editing the config

```sh
sudo nixos-rebuild switch --flake /etc/nixos#toonix
```

(Assumes you placed this repo at `/etc/nixos`; otherwise point `--flake` at
wherever the flake lives, keeping the `#toonix` output name.)

### Validating before you build

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

### Change the theme

Use Omarchy's own tooling — it works on NixOS:

```sh
omarchy-theme-set ristretto      # or: ado, aether, monokai, waffle-cat, demon, …
omarchy-theme-list               # see installed themes
```

…or open the menu (**SUPER + ALT + SPACE**) and pick Theme. The active theme
lives in `~/.config/omarchy/current/`; the installed library is in
`~/.config/omarchy/themes/`. Switches persist across `nixos-rebuild` because the
activation only seeds the active theme when none is set.

### Handy keybindings (Omarchy defaults)

- **SUPER + SPACE** — launch apps (Walker)
- **SUPER + ALT + SPACE** — Omarchy menu
- **SUPER + K** — show all keybindings
- **SUPER + RETURN** — terminal
- **SUPER + CTRL + E** — emoji/symbol picker

### Timezone

Set in `configuration.nix`: `time.timeZone = "America/Chicago";` — change it
there and rebuild.

### Disk, bootloader & swap

Mirrors the host's real Omarchy layout: **Btrfs** root with subvolumes
(`@`→/, `@home`→/home, `@nix`→/nix, `@log`→/var/log, `@snapshots`→/.snapshots,
`compress=zstd`), **GRUB** on UEFI (the menu lists every NixOS generation =
bootable rollback), and **zram** swap (no swap partition). Btrfs auto-scrub and
periodic SSD `fstrim` are enabled; **Snapper** keeps an hourly timeline of `/home`.
The host also LUKS-encrypts root — that's an opt-in here (see the commented
block in `hardware-configuration.nix` and the "Encrypted variant" note in
[INSTALL.md](./INSTALL.md)); the VM defaults to unencrypted so boot needs no
passphrase.

### Enabling NVIDIA

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

### VM notes

The guest renders on virtio-gpu via software rendering (llvmpipe) — no host GPU
passthrough needed to boot the desktop. SPICE clipboard/auto-resize and the
QEMU guest agent are enabled. For the actual install procedure, see
[INSTALL.md](./INSTALL.md).
