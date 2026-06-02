# Running Toonix in a local QEMU VM (no Nix on the host)

The Nix work happens **inside** the VM (off the NixOS installer ISO), and this
repo is shared into the guest over **9p** — so you don't need Nix installed on
your machine, and your **private repo never leaves it** (no GitHub token in the
guest).

## 0. One-time host prereqs (Arch/Omarchy)

```sh
sudo pacman -S qemu-desktop edk2-ovmf
```

## 1. Boot the installer VM (on the host)

```sh
./vm/run-toonix-vm.sh
```
First run downloads the NixOS minimal ISO and creates `vm/toonix.qcow2` (40 GB),
then boots QEMU (UEFI). Tunables: `RAM=8192 CPUS=4 DISK_SIZE=40G ./vm/run-toonix-vm.sh`.

## 2. Install Toonix (inside the VM's root shell)

```sh
mkdir -p /f && mount -t 9p -o trans=virtio,version=9p2000.L toonixflake /f
TOONIX_UNATTENDED=1 bash /f/vm/install-in-vm.sh     # add a disk arg only if not /dev/vda
```
That's **fully unattended** — no prompts. It partitions the disk (Btrfs subvolumes
matching `hardware-configuration.nix`), then `nixos-install --flake /f#toonix`,
pulling most of the closure from the binary cache and building the custom bits
(Thorium, themes). Expect ~15–40 min, then it powers down on its own readiness.
Root is left locked; you log in as **`bantam`** / **`changeme`** (wheel sudo).
(Drop `TOONIX_UNATTENDED=1` if you'd rather confirm the disk-erase first.)

## 3. Boot the installed system

```sh
poweroff          # in the VM
rm vm/nixos-minimal.iso   # optional: so it boots straight from disk
./vm/run-toonix-vm.sh     # boot again; log in at SDDM → "Hyprland (UWSM)"
```

## Notes
- `-cpu host` is used, so the SSE3-pinned Thorium runs fine (and faster).
- Software rendering (llvmpipe) drives the desktop — no GPU passthrough needed;
  `WLR_RENDERER_ALLOW_SOFTWARE` is already set in the config.
- This is the **manual/local** equivalent of the headless cloud-box deploy; CI
  already proves the config **evaluates + builds**, so this step is about seeing
  it **boot + activate** live.
- Prefer installing from GitHub instead of the 9p share? Make the repo public,
  then in the VM use `nixos-install --flake github:HighRankingBantam/toonix#toonix`.
