# The FluteOS installer image

How the image is built and what is on it. For **using** it — writing it to a USB
stick, booting, installing — see [Installation](../README.md#installation) in the
root README. This file used to duplicate those steps, and every specific in it had
drifted: filenames, hostname, the login, and paths like `modules/common.nix` and
`home/default.nix` that no longer exist.

## Files

| File | What it does |
|------|--------------|
| `default.nix` | Image settings, packages, and the flake bundled at `/iso/flute` |
| `live-features.nix` | The live system's **own** feature set |
| `live-session.nix` | The live user and autologin |
| `install-script.nix` | The `flute-install` command |

## The image is not a host

This is the design decision worth knowing before changing anything here.

`mkISO` in `flake.nix` composes **`osModules`** — the product — and no host
directory at all. The live system states its own feature set in
`live-features.nix`.

It used to be `mkISO "yoga"`, which composed a machine somebody owns. The
published x86_64 image therefore booted as that person's account, in their
timezone, with their tailnet units and their widgets, in a 21.8 GiB closure; and
because the host came from `personal/`, the image could not be built at all on a
checkout that did not have that directory. Two people building the same commit now
get the same image.

Consequences to keep in mind:

- The live system has no `disko.nix`, so its filesystems come from the installer
  media. Do not add one.
- `system.stateVersion` is forced to the current nixpkgs release: a live image
  keeps no state, and `features.base.system` plus nixpkgs' installer base each
  supply a `mkDefault`, which is a conflict rather than an override.
- `features.base.greetd` is forced off. That module configures **ly**, and the
  live session needs passwordless autologin, which `live-session.nix` sets up with
  greetd itself. With both on, two display managers raced for tty1 and greetd won
  only because systemd links unit aliases last.
- The live set is deliberately narrower than an install: the desktop profile, a
  browser, a file manager, WiFi. No dev toolchains, no media library, no
  containers — nothing that only earns its size once you have your own data on
  disk.

## What gets bundled

`isoImage.contents` copies the flake to `/iso/flute` so `flute-install` can
install from the running image. `bundledFlake` in `default.nix` filters that copy:
`personal/` is excluded outright, with a credential-shaped denylist behind it
(`*.secret`, `*.key`, `id_ed25519*`) in case something new lands outside
`personal/`, plus build-host clutter (`.claude`, `.github`, `.ruff_cache`,
`__pycache__`, `result`).

That filter governs the **source** on the image. The **system** the image boots is
kept clean separately, by `mkISO` composing `osModules` — a denylist here cannot
help with what the closure contains, which is exactly how the old image ended up
shipping a WiFi PSK rendered into a store file.

The bundle carries `hosts/`, so `flute-install` can offer `pc` (x86_64) and `live`
(aarch64). A private configuration is added on the target afterwards.

## Building

```bash
./build-iso.sh          # this machine's architecture
./build-iso.sh x86      # x86_64 explicitly
./build-iso.sh arm      # aarch64 explicitly
```

Or by hand:

```bash
nix build .#nixosConfigurations.iso.config.system.build.isoImage      # x86_64
nix build .#nixosConfigurations.iso-arm.config.system.build.isoImage  # aarch64
```

`image.baseName` is `fluteos`, so the output is `result/iso/fluteos.iso`;
`build-iso.sh` copies it to `fluteos-<arch>.iso`.

Rough build times with a warm cache: ~15–30 min for x86_64, ~45–90 min for
aarch64 (emulation is much slower — a native ARM builder is worth it).

`squashfsCompression = "lz4"` trades size for speed. Roughly: `lz4` is fastest to
build and boot, `zstd` is balanced, `xz` is smallest and slowest.

## Live session

Autologin as `user`, password `qwerty` — both throwaway, since the live system
keeps no state. `security.sudo.wheelNeedsPassword = false` so `flute-install` runs
without a prompt, and `/etc/issue` carries the install instructions for the TTY.

The user's name is read from `features.base.system.user.name` rather than written
here, so the image and the installed system agree, and no downloader gets a live
image carrying the distro author's account.

## Troubleshooting

**The ISO does not boot.** Check the firmware is in UEFI mode, not Legacy, and
disable Secure Boot — the NixOS ISO is not signed. Verify the written stick with
`sudo fdisk -l /dev/sdX`; it should report ISO 9660.

**Installation runs out of memory.** Add swap in the live session before
installing:

```bash
sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
```

**Partitioning fails.** Something is holding the disk:

```bash
sudo umount /dev/sdX*
sudo wipefs -a /dev/sdX
sudo flute-install /dev/sdX
```

**WiFi does not work.** `lspci -k | grep -A3 Network` to check the driver loaded,
`sudo rfkill unblock wifi` if it is soft-blocked, then `nmtui`.

**`flute-install` says there is no host directory.** The image carries FluteOS
only, by design. It prints the hosts it does have — pass one of those as the
second argument. `/iso/flute` is a read-only squashfs, so a private configuration
cannot be added on the running image: install a bundled template first, then add
your own repository.
