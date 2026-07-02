# Parity — what works vs. degraded on NixOS

Feature-by-feature status of the Omarchy port. See [ARCHITECTURE.md](./ARCHITECTURE.md)
for how the pieces fit together.

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
| Package parity | Improved | Added more direct mappings from `omarchy/install/omarchy-base.packages`: Docker compose/buildx, FAT/exFAT tools, ALSA utilities, `less`, `qalc` (`libqalculate`), `tree-sitter`, `usage`, DB client libraries (`libpq`/MariaDB connector), Typora, 1Password GUI/CLI, WebP pixbuf support, MTP/NFS helpers, `tzupdate`, and the pinned upstream Nix flake for `hyprland-preview-share-picker` |
| Mimetypes / XDG dirs / XCompose | Works | Omarchy's imv·mpv·evince·nvim defaults, disabled Templates/Public/Desktop, writable GTK/Nautilus bookmarks, and CapsLock-compose emoji (`modules/omarchy-home-extras.nix`) |
| GNOME/GTK defaults + keyring | Works | Omarchy first-run defaults are declarative: dark GTK/color scheme, ristretto's Yaru-yellow icons, primary-paste enabled, and passwordless `Default_keyring` seeded only if absent (`modules/omarchy-home-extras.nix`) |
| Omarchy assistant skill | Works | `install/config/omarchy-ai-skill.sh` is ported: the bundled Omarchy skill is symlinked into `~/.agents`, `~/.claude`, `~/.codex`, and `~/.pi/agent` skill directories |
| App-menu launchers + declutter | Works | Omarchy's Alacritty/imv/mpv/typora launchers + 34 `Hidden=true` entries (avahi-discover, java/fcitx config tools, electron stubs…) + webapp icons, installed to `~/.local/share/applications` (`omarchy-home.nix` step 9) |
| Web apps | Works | All 15 (ChatGPT, YouTube, WhatsApp, HEY, GitHub, X, Figma, Discord, Zoom, Google {Photos,Maps,Messages,Contacts}, Basecamp, Fizzy) generated as `.desktop` launchers that open as Thorium `--app` windows (`modules/omarchy-webapps.nix`); copy-url extension (Alt+Shift+L) wired into Thorium |
| TUI launchers | Works | Disk Usage (dust) + Docker (lazydocker) open in floating/tiled terminals via `xdg-terminal-exec` (`omarchy-webapps.nix`) |
| Terminal selection | Works | `omarchy-install-terminal` is shadowed with a NixOS-safe implementation that selects among the already-declared terminals instead of invoking pacman |
| Dictation / Voxtype | Partial | `pkgs.voxtype` is declared and a writable config is seeded. `omarchy-voxtype-install` is shadowed to download the model and enable the user service without pacman; model download remains opt-in |
| Branding / toggles | Works | fastfetch logo (`branding/about.txt`) + screensaver text + `~/.local/state/omarchy/toggles/hypr/flags.conf` all seeded (`omarchy-home.nix` steps 3 & 7) |
| Browsers | Works | **Floorp** (`floorp-bin`, with Omarchy's Firefox VAAPI/Wayland policies applied) replaces Firefox; **Thorium** replaces Chromium and is the default — web apps resolve to it via a `chromium.desktop`→Thorium alias. Thorium isn't in nixpkgs so it's packaged from the official AppImage, pinned to a real release+hash — **builds as-is, no manual step** (see the Thorium note below to pick the CPU variant / bump the version) |
| Git config | Works | Omarchy's `config/git/config` ported into `programs.git` (aliases co/br/ci/st, rerere, histogram diff, push.autoSetupRemote, …) |
| Screen recording / sharing | Works | `programs.gpu-screen-recorder.enable` installs Omarchy's recorder and the setcap wrapper it needs; `wl-screenrec` is also installed as a fallback. Screenshots/OCR use grim/slurp/satty/tesseract. Portal screen sharing uses Omarchy's configured `hyprland-preview-share-picker` binary |
| Debug / hardware helpers | Works | `omarchy-debug` and `omarchy-upload-log` are shadowed with NixOS reports instead of pacman/expac output; Fastfetch version/channel/update helpers are NixOS-aware; `omarchy-hw-vulkan` checks NixOS OpenGL/Vulkan driver paths plus `vulkaninfo` |
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

## Thorium (packaged from the official AppImage)

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
