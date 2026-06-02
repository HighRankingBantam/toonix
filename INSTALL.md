# Installing into a QEMU VM

Step-by-step install of this flake (Omarchy v3.8.2 on NixOS) into a QEMU/KVM
guest. The flake output is **`nixos-vm`**; the login user is **`bantam`** with
initial password **`changeme`**.

> Assumes a **UEFI** VM (QEMU with OVMF firmware) and a single virtio disk
> (`/dev/vda`). Give it ~4+ CPUs, 8 GB RAM, and ≥40 GB disk. The desktop renders
> via software (llvmpipe), so 3D acceleration is not required to boot.
>
> **CPU model:** the Thorium browser is pinned to the **SSE3** build by default,
> which runs on the default `qemu64` vCPU. If you prefer, boot with `-cpu host`
> (libvirt: "Copy host CPU configuration") and flip `cpuVariant` to `"SSE4"`/
> `"AVX2"` in `modules/omarchy-browsers.nix` for a faster browser. Everything
> else works on `qemu64` as-is.
>
> **Filesystem:** Btrfs with subvolumes (`@`, `@home`, `@nix`, `@log`,
> `@snapshots`), `compress=zstd`. **Bootloader:** GRUB (UEFI). **Swap:** zram
> (RAM-backed) — no swap partition needed. This mirrors the host's real Omarchy
> layout (which also LUKS-encrypts root — see the "Encrypted variant" note at
> the end if you want that too).

---

## 1. Boot the NixOS minimal ISO (UEFI)

Attach the [NixOS minimal ISO](https://nixos.org/download/) to the VM and boot
it in **UEFI** mode. You'll land at a root shell prompt.

Confirm you booted UEFI (this dir must exist):

```sh
ls /sys/firmware/efi/efivars
```

---

## 2. Partition `/dev/vda` (GPT: 2 GiB ESP + rest Btrfs)

```sh
parted /dev/vda -- mklabel gpt
parted /dev/vda -- mkpart ESP fat32 1MiB 2GiB
parted /dev/vda -- set 1 esp on
parted /dev/vda -- mkpart root btrfs 2GiB 100%
```

> The ESP is 2 GiB (not the usual 512 MiB–1 GiB) because GRUB copies every NixOS
> generation's kernel + initrd onto it; with `configurationLimit = 20` (set in
> `configuration.nix`) that's ~1.5 GB, so a 1 GiB ESP would eventually fill and
> break `nixos-rebuild`. 2 GiB gives comfortable headroom.

This gives you `/dev/vda1` (ESP) and `/dev/vda2` (Btrfs root).

---

## 3. Make filesystems, create Btrfs subvolumes, and mount

Label them to match `hardware-configuration.nix` (`BOOT` for the ESP, `nixos`
for the Btrfs root). You regenerate the hardware config in step 4 anyway, but
the labels keep things consistent:

```sh
mkfs.fat -F32 -n BOOT /dev/vda1
mkfs.btrfs -L nixos /dev/vda2

# Create subvolumes (@ = root, plus home/nix/log/snapshots)
mount /dev/disk/by-label/nixos /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@nix
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@snapshots
umount /mnt

# Re-mount each subvolume with zstd compression
o=compress=zstd,noatime
mount -o subvol=@,$o          /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/{home,nix,var/log,.snapshots,boot}
mount -o subvol=@home,$o      /dev/disk/by-label/nixos /mnt/home
mount -o subvol=@nix,$o       /dev/disk/by-label/nixos /mnt/nix
mount -o subvol=@log,$o       /dev/disk/by-label/nixos /mnt/var/log
mount -o subvol=@snapshots,$o /dev/disk/by-label/nixos /mnt/.snapshots
mount /dev/disk/by-label/BOOT /mnt/boot
```

---

## 4. Generate hardware config, then drop in this repo

Generate the NixOS config skeleton:

```sh
nixos-generate-config --root /mnt
```

This writes `/mnt/etc/nixos/configuration.nix` and
`/mnt/etc/nixos/hardware-configuration.nix`. Now **replace `/mnt/etc/nixos`
with this repo, but KEEP the generated `hardware-configuration.nix`** (it has
your VM's real disk UUIDs, filesystems, and kernel modules):

```sh
# Save the auto-detected hardware config
cp /mnt/etc/nixos/hardware-configuration.nix /tmp/hardware-configuration.nix

# Put this repo at /mnt/etc/nixos (clone, or copy from a mounted share / USB)
rm -rf /mnt/etc/nixos
git clone <this-repo-url> /mnt/etc/nixos

# Restore the generated hardware config, overwriting the repo's placeholder
cp /tmp/hardware-configuration.nix /mnt/etc/nixos/hardware-configuration.nix
```

> If you don't have network/git in the ISO, copy the repo over however you
> prefer (9p/virtfs share, scp, USB). The only hard requirement is that
> `/mnt/etc/nixos` ends up containing this repo **plus the generated
> `hardware-configuration.nix`** (not the committed placeholder).

---

## 5. Install

```sh
nixos-install --flake /mnt/etc/nixos#nixos-vm
```

The build is large (full Hyprland desktop + apps), so this takes a while. The
user `bantam` is created with initial password **`changeme`**
(`nixos-install` may also prompt for the root password — set one you'll
remember).

When it finishes:

```sh
reboot
```

Remove the ISO from the VM so it boots from disk.

---

## 6. First boot

1. The **GRUB** menu appears first — it lists every NixOS generation (your
   bootable rollback history) and boots the latest automatically.
2. At the **SDDM** login screen, pick the session **"Hyprland (UWSM)"** (use the
   session selector if another session is preselected).
3. Log in as **`bantam`** / **`changeme`**.
4. The Omarchy desktop comes up with the **ristretto** theme. Change your
   password (`passwd`) at your convenience.

---

## 7. After install

Subsequent changes are applied by rebuilding against the same flake output:

```sh
sudo nixos-rebuild switch --flake /etc/nixos#nixos-vm
```

See [README.md](./README.md) for day-to-day usage — theme switching, which
`omarchy-*` commands are safe vs. Arch-only, keybindings, and the NVIDIA opt-in.

---

## Appendix: Encrypted variant (LUKS, like the real host)

The real Omarchy host encrypts root (LUKS2 → `/dev/mapper/root`). The steps
above leave it **unencrypted** so the VM boots without a passphrase. To
reproduce encryption, change step 2–3 like so:

```sh
# Partition: same ESP, but the root partition becomes a LUKS container
parted /dev/vda -- mklabel gpt
parted /dev/vda -- mkpart ESP fat32 1MiB 2GiB
parted /dev/vda -- set 1 esp on
parted /dev/vda -- mkpart root 2GiB 100%

mkfs.fat -F32 -n BOOT /dev/vda1

# Create + open the LUKS2 container, then put Btrfs INSIDE it
cryptsetup luksFormat --type luks2 /dev/vda2
cryptsetup open /dev/vda2 root            # → /dev/mapper/root
mkfs.btrfs -L nixos /dev/mapper/root
```

Then create/mount the subvolumes exactly as in step 3 but against
`/dev/mapper/root` instead of `/dev/disk/by-label/nixos`. Run
`nixos-generate-config --root /mnt` **while the LUKS device is open** — it will
auto-write the `boot.initrd.luks.devices."root"` entry and point the
`fileSystems` at `/dev/mapper/root`. (The committed `hardware-configuration.nix`
also shows this block, commented, for reference.) You'll be prompted for the
passphrase on every boot.
