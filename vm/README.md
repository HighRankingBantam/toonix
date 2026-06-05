# Running Toonix in a local QEMU VM (no Nix on the host)

The Nix work happens **inside** the VM (off the NixOS installer ISO), so you
don't need Nix installed on your machine. The normal path downloads Toonix from
GitHub with a single `curl` command. The host repo is still shared into the
guest over **9p** for local fallback testing.

## 0. One-time host prereqs (Arch/Omarchy)

```sh
sudo pacman -S qemu-desktop edk2-ovmf
```

## 1. Boot the installer VM (on the host)

```sh
./vm/run-toonix-vm.sh
```
First run downloads the NixOS minimal ISO and creates `vm/toonix.qcow2` (40 GB),
then boots QEMU (UEFI). Tunables:

```sh
RAM=8192 CPUS=4 DISK_SIZE=40G ./vm/run-toonix-vm.sh
HEADLESS=1 ./vm/run-toonix-vm.sh       # serial installer in this terminal
BOOT=disk ./vm/run-toonix-vm.sh        # boot the installed disk, no ISO
```

## 2. Install Toonix from the internet (inside the VM's installer shell)

```sh
curl -fsSL https://raw.githubusercontent.com/HighRankingBantam/toonix/main/install.sh | sudo TOONIX_UNATTENDED=1 bash
```

That downloads the current `main` branch, partitions the disk (Btrfs subvolumes
matching `hardware-configuration.nix`), copies the fetched flake to
`/mnt/etc/nixos`, then runs `nixos-install --flake /mnt/etc/nixos#toonix`,
pulling most of the closure from the binary cache and building the custom bits
(Thorium, themes). Expect ~15–40 min.

Root is left locked; you log in as **`bantam`** / **`changeme`** (wheel sudo).
Drop `TOONIX_UNATTENDED=1` if you'd rather confirm the disk erase first.

To install to a disk other than `/dev/vda`, pass it after `bash`:

```sh
curl -fsSL https://raw.githubusercontent.com/HighRankingBantam/toonix/main/install.sh | sudo TOONIX_UNATTENDED=1 bash -s -- /dev/sda
```

This requires the GitHub repo/archive to be reachable from the installer VM. To
test another branch or archive, set `TOONIX_BRANCH=...` or
`TOONIX_ARCHIVE_URL=...` before `bash`.

### Local fallback without internet

```sh
sudo mkdir -p /f && sudo mount -t 9p -o trans=virtio,version=9p2000.L toonixflake /f
sudo TOONIX_UNATTENDED=1 bash /f/vm/install-in-vm.sh     # add a disk arg only if not /dev/vda
```

## 3. Boot the installed system

```sh
poweroff          # in the VM
BOOT=disk ./vm/run-toonix-vm.sh     # log in at SDDM → "Hyprland (UWSM)"
```

## Notes
- `-cpu host` is used when KVM is available; otherwise the script uses
  `-cpu max` for TCG/software emulation. You can override with `CPU=...`.
- Software rendering (llvmpipe) drives the desktop — no GPU passthrough needed;
  `WLR_RENDERER_ALLOW_SOFTWARE` is already set in the config.
- This is the **manual/local** equivalent of the headless cloud-box deploy; CI
  already proves the config **evaluates + builds**, so this step is about seeing
  it **boot + activate** live.
- Prefer installing from GitHub instead of the 9p share? Make the repo public,
  then in the VM use `nixos-install --flake github:HighRankingBantam/toonix#toonix`.
