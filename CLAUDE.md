# CLAUDE.md — agent context for Toonix (the NixOS Omarchy port)

> Engineering context for working on this repo. User-facing docs are
> `README.md` (architecture) and `INSTALL.md` (QEMU install). This file is the
> "what an agent needs to know to continue safely" doc — decisions, gotchas,
> and what NOT to do. Created 2026-05-29.

## What this is

A NixOS flake (output `toonix`) that recreates the user's **Omarchy v3.8.2**
Hyprland desktop on NixOS, to run in a **QEMU VM**. Goal: bring the user's
existing config along so they don't reconfigure on install. Claude Code is
preinstalled (original user request). Working dir of the broader session is
`~/Projects`; this project lives at `~/Projects/nixos/` (a local git repo;
GitHub push still pending `gh auth login`).

## Critical context (read before editing)

- **Version: Omarchy v3.8.2**, which is **`.conf`-based** (Hyprland sources
  `.conf` files). Do **NOT** pull `main`/v4.x — that branch is Lua-based and a
  totally different layout. The first attempt made this mistake; the bundled
  `omarchy/` tree is pinned to **v3.8.2** (matches the user's live machine).
- **Active theme: `ristretto`** (coral/burgundy: accent `#f38d70`, bg `#2c2525`).
  NOT Tokyo Night. The rendered theme seed is `user-configs/omarchy-current/`.
- **Target is a QEMU VM.** The user's *host* is NVIDIA (Turing+), but the VM
  uses virtio-gpu. NVIDIA is an **opt-in commented block** in `configuration.nix`
  — do not enable it by default or the VM black-screens.
- **Disk/boot (matches the host's real layout, verified via lsblk/findmnt):**
  **Btrfs** root with subvolumes `@`→/, `@home`→/home, `@nix`→/nix (replaces the
  host's Arch-only `@pkg`), `@log`→/var/log, `@snapshots`→/.snapshots,
  `compress=zstd`. **GRUB** on UEFI (not systemd-boot — user asked for GRUB;
  Omarchy itself uses Limine). **zram** swap. **Snapper** hourly timeline on
  /home. Host also **LUKS2-encrypts** root → opt-in commented block in
  `hardware-configuration.nix` (VM defaults unencrypted for passphrase-free boot).
- **Timezone: America/Chicago.**
- **No Nix binary in this environment.** Can't run `nix flake check` /
  `nixos-rebuild` here. Validation done = bash syntax + functional activation
  dry-run into a throwaway `$HOME` + nixpkgs attr names AND option schemas
  (snapper/grub/zram/btrfs) web-verified against nixpkgs master. The config has
  **not been built or booted** yet. Real test = `nixos-install` in the VM.

## Architecture (the one big decision)

Omarchy is **self-mutating**: theme switches `rm -rf ~/.config/omarchy/current && mv`,
toggles write `~/.local/state/omarchy/`, the menu rewrites `~/.config`. So we
do **NOT** use read-only `home.file` store symlinks for configs (they'd break
all of that with permission errors). Instead:

- `modules/omarchy-runtime.nix` — one read-only symlink `omarchy/` →
  `~/.local/share/omarchy` (the engine; 282 scripts resolve relative to it).
- `modules/omarchy-home.nix` — a **Home-Manager activation script** that copies
  Omarchy's configs into `~/.config` **writable** (`cp -Rf` + `chmod u+w`),
  mirroring upstream `install/config/config.sh`. Seeds `~/.config/omarchy/current`
  (ristretto), the theme library, mako/btop theme symlinks, pre-marks all 325
  migrations, creates `~/.local/state/omarchy/toggles/hypr`. Runtime state is
  seeded **only-if-absent** so `nixos-rebuild` never clobbers an in-VM theme switch.
- `configuration.nix` — also carries Omarchy's networking/runtime system bits:
  systemd-resolved stub DNS, Docker bridge DNS listener, socket-activated Docker
  with bounded JSON logs, LocalSend's TCP/UDP firewall allowance, and printer
  discovery via Avahi + cups-browsed + CUPS-PDF/system-config-printer. It also
  contains the main package parity set from `omarchy/install/omarchy-base.packages`
  (Docker compose/buildx, filesystem tools, qalc/tree-sitter/WebP pixbuf, etc.).
- `modules/omarchy-home-extras.nix` — declarative ports of home-level install,
  first-run, and login bits: mimetypes/XDG dirs/XCompose/WirePlumber, GNOME
  dconf defaults, Elephant user service, passwordless Default_keyring, Omarchy
  assistant skill symlinks, ~/Work, Nautilus extensions.
- `modules/omarchy-nixos-compat.nix` — stub scripts that no-op the Arch-only
  commands; PATH-win applied in `shell.nix` (must run after Omarchy's rc).
- `modules/shell.nix` — sources Omarchy's bash framework; fzf integration; the
  compat PATH prepend.
- Session: SDDM + `programs.hyprland.withUWSM = true` (auto-generates
  `hyprland-uwsm.desktop`; ships `uwsm-app` that all bindings call).

The `omarchy-home.nix` activation now has **10 steps**: (1) stock configs,
(2) user overrides, (3) ~/.config/omarchy + branding, (4) theme library,
(5) active theme, (6) mako/btop theme symlinks, (7) toggles + migrations,
(8) omarchy.ttf, (9) app launchers / menu declutter / icons, (10) walker
autostart + elephant menus (the in-launcher Theme/Background/Unlocks menus).

**Bundled-tree coverage (verified):** all 28 `omarchy/default/` subdirs are
wired, sourced via the runtime symlink, or skipped with reason. Justified skips
(can't/shouldn't port): `limine` (GRUB instead), `pacman` (Arch N/A),
`pi` (tool not in nixpkgs), `wayland-sessions` (withUWSM). Don't
re-investigate these as "missing" — they're deliberate. (`default/snapper/root`
IS ported — `services.snapper.configs.root` in configuration.nix, NUMBER-based,
limit 5 — though GRUB generations remain the primary system rollback.)

## Gotchas (hard-won — don't reintroduce)

0. **Activation step-3 `makeWritable` prunes `themes/` + `current/`** — do NOT
   change it back to `makeWritable "$cfg/omarchy"`; that `chmod`s the 229 MB theme
   library on *every* rebuild. Those two are made writable once at seed time
   (steps 4 & 5). Module arg lists are trimmed to only what's used (`deadnix`);
   `.config` files use `xdg.configFile`, not `home.file.".config/…"`.

1. **`cp -Rf`, never `cp -RfL`** in the activation. `hypr/shaders/*.glsl` are
   symlinks into `/usr/share/aether` (AUR pkg, no nixpkgs build) → dangling here.
   `-L` (dereference) aborts the whole activation under `set -e`. Preserve links.
2. **`services.swayosd` is Home-Manager-only**, NOT a NixOS option. It lives in
   `home.nix`. Putting it in `configuration.nix` fails evaluation.
3. **`home.file = {…}` AND `home.file."x" = …` in one attrset = parse error**
   ("attribute already defined"). If you ever go back to home.file, use
   dot-notation throughout one attrset, or split across modules.
4. **`withUWSM` already generates the session** — do NOT hand-write
   `/etc/sddm/sessions/*.desktop` (wrong dir; Wayland sessions are
   `wayland-sessions/`) or a second `waylandCompositors` entry (duplicate).
5. **Compat-stub PATH precedence:** Omarchy re-prepends `$OMARCHY_PATH/bin` in
   BOTH `default/bash/envs` (every interactive shell) and `~/.config/uwsm/env`
   (graphical session), so the override dir must be prepended **after** each:
   `shell.nix` initExtra handles interactive shells; `user-configs/uwsm/env`
   (the override-dir line appended after Omarchy's) handles GUI/menu-launched
   commands. A plain `home.sessionPath` loses to both. Don't remove either.
6. **`elephant` is required** for the Walker launcher (SUPER+SPACE) to return
   results; it's `pkgs.elephant` (packaged). It is enabled as a Home-Manager
   user service so `omarchy-restart-walker` restarts it; `omarchy-launch-walker`
   still starts it lazily if the service is not running yet.
7. **`nixpkgs.config.allowUnfree = true`** is required (claude-code, obsidian,
   spotify, _1password-cli).
8. **Activation step-1 skip-list = `omarchy|git|chromium|hypr|uwsm|walker|alacritty|systemd`.**
   omarchy=runtime state, git=`programs.git`, chromium=browser-rewritten,
   hypr/uwsm/walker/alacritty=user overrides. **`systemd` is critical**: home-manager
   owns `~/.config/systemd/user` (e.g. `swayosd.service`), so a `rm -rf ~/.config/systemd`
   in step 1 would delete HM's units every rebuild (broke the OSD). Don't drop it
   from the skip-list. The stock omarchy systemd units are laptop-only/superseded.
9. **`services.snapper` keys are UPPERCASE** (`SUBVOLUME`, `ALLOW_USERS`,
   `TIMELINE_*`) — source-verified; the module *asserts-fails* on lowercase
   `subvolume`/`extraConfig`. Do NOT "fix" them to lowercase.
10. **`services.locate`: do NOT add `localuser`** — it was removed
    (`mkRemovedOptionModule`, throws if set). `package = pkgs.plocate` is the
    default; `{ enable; package = pkgs.plocate; interval = "weekly"; }` is correct.
11. **Floorp = `pkgs.floorp-bin`** (NOT `pkgs.floorp` — removed/throws).
    **Thorium isn't in nixpkgs** — packaged from the official AppImage in
    `modules/omarchy-browsers.nix`, **pinned to a real release + both hashes**
    (`M138.0.7204.303`). `cpuVariant` defaults to **SSE3** (default qemu64 lacks
    SSE4 → SSE4/AVX2 would SIGILL); flip to "SSE4" for `-cpu host`/real hardware.
    To bump: update `thoriumVersion` + refresh `thoriumHashes`. A `chromium.desktop`→Thorium alias
    makes Omarchy's webapps resolve to Thorium. Webapps + TUI launchers are
    generated in `modules/omarchy-webapps.nix`.
12. **`kdePackages.kdenlive`, NOT bare `kdenlive`** (the top-level attr doesn't
    exist on unstable → "attribute missing"). Same for other KDE apps.
13. **No `permittedInsecurePackages` needed** — obsidian (1.12.7) pins
    `electron_40`, above the insecure cutoff. Don't add a stale electron string;
    if obsidian ever re-pins an EOL electron, the build error prints the exact
    string to add. Also: `signal-desktop` (NOT `-bin`, which now throws). **1Password
    is now via the NixOS modules** `programs._1password` + `programs._1password-gui`
    (`polkitPolicyOwners = ["bantam"]`) — these add the setgid browser-integration
    + polkit helpers a bare `_1password`/`_1password-cli` systemPackages entry would
    miss. Do NOT revert to a plain package entry.

## Do NOT run on the VM (and why they're stubbed)

`omarchy update`, `omarchy-refresh-{pacman,sddm,plymouth,limine}`,
`omarchy-toggle-hybrid-gpu`, `omarchy-pkg-*`, and the Arch package
install/remove/setup flows all call pacman/yay or write `/etc`,`/usr`,`/boot`.
NixOS owns packages/boot/SDDM/Plymouth declaratively. `omarchy-nixos-compat.nix`
shadows them with explicit NixOS messages so they fail fast instead of leaving
partial state. Migrations are also pre-marked done so nothing replays them.

NixOS-specific shims that are allowed: `omarchy-update-firmware` calls
`fwupdmgr` through `services.fwupd`, `omarchy-install-terminal` only switches
among terminals already declared in `environment.systemPackages`, `omarchy-debug`
and `omarchy-upload-log` print NixOS reports instead of pacman output,
Fastfetch version/channel/update helpers are NixOS-aware, and `omarchy-hw-vulkan`
checks NixOS OpenGL/Vulkan driver paths.

## Known-degraded (acceptable for a test VM)

- Keyboard-RGB theme steps (asusctl/qmk_hid) — guarded no-ops, hardware-specific.
- Browser theme policy writes to `/etc/*/policies` — guarded, silently skip.
- AUR-only apps omitted: aether, cliamp, omarchy-nvim, tobi-try, ttf-ia-writer
  (see omitted list in `configuration.nix`). 1Password GUI/CLI, Typora,
  Voxtype, `usage`, `tzupdate`, and the direct DB/client-library mappings are
  now ported through nixpkgs/NixOS modules or shims. `hyprland-preview-share-picker`
  is ported through its pinned upstream Nix flake input.

## File map

```text
flake.nix                 nixosConfigurations.toonix + Home-Manager; checks (nix flake check) + formatter (nix fmt)
justfile                  `just` helpers (switch/test/build/check/vm/update/gc/fmt); .github/workflows/check.yml = CI
configuration.nix         system: GRUB(UEFI), btrfs, zram, snapper, SDDM+Hyprland/UWSM, audio, fonts, packages
                          resolved + Docker bridge DNS + LocalSend firewall + cups-browsed printer discovery; imports → modules/system-tweaks.nix + modules/omarchy-branding.nix
hardware-configuration.nix Btrfs-subvolume TEMPLATE (+opt-in LUKS) — replace w/ nixos-generate-config at install
home.nix                  HM entry: imports 6 home modules, git, session env, services.swayosd
modules/ (system)         system-tweaks.nix (install/config/* tweaks: sysctl/fd/sudo/wifi/regdom/logind/usb/fuse) · omarchy-branding.nix (SDDM+Plymouth themes)
modules/ (home-manager)   omarchy-runtime · omarchy-home · omarchy-home-extras (mime/xdg/xcompose/wireplumber)
                          · omarchy-browsers (floorp-bin + Thorium AppImage) · omarchy-nixos-compat · shell
omarchy/                  bundled upstream v3.8.2 (read-only) — bin/ config/ default/ themes/ migrations/
user-configs/             user's real hypr/uwsm/walker/alacritty/mako + omarchy-current (ristretto) + omarchy-hooks + omarchy-themes (~229M)
README.md / INSTALL.md    user-facing docs
```

## Browsers (user swapped them in)

- **Floorp replaces Firefox** → `pkgs.floorp-bin` (NOT `pkgs.floorp` — that attr
  was removed/throws in 2025). Defined in `modules/omarchy-browsers.nix`
  (`home.packages`). Desktop file `floorp.desktop`, profile dir `~/.floorp`.
- **Thorium replaces Chromium** → NOT in nixpkgs; packaged from the official
  AppImage via `appimageTools.wrapType2` in `modules/omarchy-browsers.nix`.
  Needs `thoriumVersion`/URL/hash filled (hash via `lib.fakeHash` → first build
  prints real one). Omarchy is chromium-keyed, so a `chromium.desktop`→Thorium
  alias (xdg.desktopEntries) makes web apps resolve to Thorium. Default browser
  set via `xdg.mimeApps` → `thorium-browser.desktop`. `firefox`/`chromium` were
  removed from `configuration.nix` systemPackages.

## How to test

On ANY machine with Nix (validate without installing):
`nix flake check --no-build` (eval the whole config) or `nix flake check` (also
build the closure); `nix fmt` to format; `just` lists helper recipes
(`just vm` boots it in a throwaway QEMU VM via `nixos-rebuild build-vm`).

In the VM (full install): per `INSTALL.md` — partition `/dev/vda`, `nixos-generate-config --root /mnt`,
drop this repo at `/mnt/etc/nixos` **keeping the generated
hardware-configuration.nix**, then
`nixos-install --flake /mnt/etc/nixos#toonix`. Rebuild after edits:
`sudo nixos-rebuild switch --flake /etc/nixos#toonix`. First boot: pick
**"Hyprland (UWSM)"** in SDDM, log in `bantam` / `changeme`.

## Coverage: finish-porting pass (2026-06-10)

A full gap audit of `omarchy/install/{config,first-run,login,packaging,preflight,
post-install}` + the `.packages` manifests against the Nix config found parity
already very high. Gaps closed in this pass:

- **SDDM autologin → Hyprland** (`login/sddm.sh`): `services.displayManager.autoLogin`
  + `defaultSession = "hyprland-uwsm"`. Matches Omarchy's boot-to-desktop default.
  If you want a greeter instead, drop the autoLogin block.
- **Keyring PAM** (`login/{default-keyring,sddm}.sh`): `enableGnomeKeyring = false`
  on the `login`/`sddm`/`sddm-autologin` PAM stacks, so NixOS doesn't spawn an
  encrypted login keyring competing with Omarchy's seeded *passwordless* one.
- **`sushi`** added (Nautilus spacebar preview) — the old "no nixpkgs equiv"
  omit-comment was wrong (`pkgs.sushi` exists).
- **`terminaltexteffects` (`tte`) added** — an earlier omit-comment claimed it
  was installer-only ASCII art; WRONG: `omarchy-launch-screensaver` requires it
  and hypridle triggers the screensaver after 2.5 min idle. It's a runtime
  feature.
- **Docker `DefaultDependencies=no`** (`docker.sh`) via `systemd.services.docker.unitConfig`.
- **`omarchy-battery-monitor.{service,timer}` + `omarchy-recover-internal-monitor.service`**
  ported as `systemd.user.*` in `omarchy-home-extras.nix` (faithful to
  `omarchy/config/systemd/user/*`). Both self-guard → no-ops in the VM, live on
  the Framework-16 host.

Remaining **intentional** skips (do not re-flag as gaps):
- `welcome.sh` first-login notify-send cheatsheet toast — cosmetic/transient.
- `theme.sh` Yaru→Adwaita `go-previous/next` action-icon symlinks — cosmetic
  (Nautilus toolbar arrows); the store-path/Yaru-scalable-actions path is
  uncertain, not worth a build-time guess.
- `increase-lockout-limit.sh` PAM **faillock** half — NixOS ships no faillock
  module; `passwd_tries=10` (the sudo half) is ported. Looser-lockout intent is
  moot on a single-user VM.
- `packaging/nvim.sh` LazyVim bootstrap (ships with AUR `omarchy-nvim`) and
  `packaging/npx.sh` mise-npx CLIs (codex/gemini/etc.) — user-installable; the
  `omarchy-npx-install`/`omarchy-nvim-setup` paths exist. `neovim`/`opencode`
  are packaged natively.
- `battery-monitor` low-battery alert & `hibernation.sh` are correct VM skips but
  become real gaps on bare-metal (the battery units above now cover the former;
  hibernate needs a real (non-zram) swap + `boot.resumeDevice` on the host).

## Open / future work

- Has **not** been built or booted — first `nixos-rebuild`/install may surface
  eval issues no local check could catch (esp. option renames on nixos-unstable).
- If Hyprland won't start in QEMU, fix is enabling 3D accel on the QEMU side
  (virtio-gpu-gl + virgl), not more Nix config. Don't rathole on this.
- The 229 MB theme library bloats the flake closure; trim
  `user-configs/omarchy-themes/` if store size matters.
