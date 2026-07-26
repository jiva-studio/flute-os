```
  _____ _       _          ___  ____
 |  ___| |_   _| |_ ___   / _ \/ ___|
 | |_  | | | | | __/ _ \ | | | \___ \
 |  _| | | |_| | ||  __/ | |_| |___) |
 |_|   |_|\__,_|\__\___|  \___/|____/

    🎵 Declarative NixOS with Niri 🎵
```

# Flute OS

**A declarative NixOS distribution** featuring the Niri scrollable tiling
compositor, a modal which-key launcher, project workspaces, and Catppuccin Mocha
theming throughout.

> *Light, fast, customizable - like the sound of a flute* 🎶

Everything is a feature toggle. A host says what it *is* —
`features.profiles.desktop = true`, a browser, a timezone — and FluteOS derives
the rest: the bar only shows chips whose features are on, the launcher only lists
applications that are installed, and no keybinding points at a binary that is not
there.

## Try it

```bash
./build-iso.sh              # installer image for this machine's architecture
sudo dd if=fluteos-x86_64.iso of=/dev/sdX bs=4M status=progress
```

The image boots straight into the desktop as `user` / `qwerty`, with
`flute-install` on `$PATH`. It carries no private configuration — see
[Installation](#installation).

## Features

### Desktop

- **Niri** — scrollable tiling Wayland compositor
- **WezTerm** — GPU terminal, with project-aware tab badges
- **which-key** — modal menu on `MOD + Space`; every menu is derived from
  enabled features
- **Fuzzel** — fuzzy pickers (emoji, tailnets, agents, workspaces)
- **Mako** — notifications
- **swaylock** + **greetd** — locking and login

### Shell & tools

- **Fish** with Starship prompt
- **Neovim** (LazyVim)
- **Git** with delta
- **Claude Code** and **opencode** — AI agents, with MCP servers registered
  declaratively
- **CLI utilities** — ripgrep, fd, bat, eza, fzf, btop, jq, yq, lazygit

### Waybar chips

The bar's layout is *derived* from the features a host enables, so nothing below
renders as a dead chip on a machine that has the feature off. Built-ins — clock,
CPU, memory, battery, network, volume, tray — are always there.

| Chip | Feature |
|------|---------|
| Workspace name | `features.fluteos.workspaces` |
| Window list (niri minimap) | `features.base.niri` |
| MPD, with prev/next | `features.base.mpd` |
| Obsidian tasks | `features.base.obsidian` |
| Claude token usage, and agent status | `features.fluteos.claude-usage`, `features.fluteos.agents` |
| Push-to-talk mode | `features.fluteos.ptt` |
| Weather | `features.fluteos.weather` |
| Tailnets connected | `features.fluteos.tailnets` |

Anything else plugs in through `features.fluteos.waybar.extraModules`, which
carries the chip's definition, where it sits on the bar, and its CSS together.

### Applications

FluteOS packages these behind feature toggles; a host enables the ones it wants,
and the launcher lists exactly those:

Firefox (with per-profile windows), Obsidian, Zathura, Foliate, DigiKam,
Telegram, Teams, 1Password, Yazi, Nautilus, MPD/ncmpcpp.

Anything installed outside a feature — straight from `home.packages` — joins the
launcher through `features.fluteos.apps.extraApps`.

### System

- PipeWire audio, Bluetooth, NetworkManager, SSH
- Screen capture portal, power profiles, early-OOM protection
- Push-to-talk dictation (`features.fluteos.ptt`) with pluggable STT/LLM backends
- Syncthing (`features.base.nas`)
- Userspace Tailscale, one daemon per tailnet, all reachable at once
  (`features.fluteos.tailnets`)
- Project workspaces: a group/project tree becomes niri workspaces, terminal
  tabs, browser profiles, `.envrc` files and a docs server
  (`features.fluteos.projects`)

## Architecture

Two layers, and nothing else:

- **`features/`** — option-driven modules. Nothing here names a person, a
  machine, an account or a network.
- **`hosts/`** — distributable host templates: `pc` (x86_64) and `live`
  (aarch64).

A personal configuration is a **separate repository** that imports
`nixosModules.fluteos` and supplies its own hosts and data — see
[Using FluteOS without forking it](#using-fluteos-without-forking-it). That is
why this repo has no `personal/` directory to delete: the boundary is structural
rather than a promise.

```
flute-os/
├── flake.nix                    # nixosConfigurations.{pc,live,iso,iso-arm}
│                                # nixosModules.fluteos — the consumable module set
│
├── features/
│   ├── profiles/                # Bundles: features.profiles.{desktop,dev}
│   ├── base/                    # NixOS + home-manager wrappers (options: features.base.*)
│   │   ├── system/              # user.{name,realName,email,initialPassword}, boot, locale
│   │   ├── niri/                # compositor, keybindings, window rules, session restore
│   │   ├── terminal/            # WezTerm + project badges
│   │   ├── nas/                 # Syncthing devices/folders as options
│   │   ├── wifi/                # WiFi profiles (empty by default)
│   │   └── …                    # 35+ modules: audio, bluetooth, firefox, yazi, …
│   │
│   ├── fluteos/                 # FluteOS-specific UX (options: features.fluteos.*)
│   │   ├── theme/               # One theme tree, read by every UI module
│   │   ├── waybar/              # Status bar; extraModules is the extension point
│   │   ├── which-key/           # Modal menu
│   │   ├── apps/                # Launcher list, derived from enabled features
│   │   ├── projects/            # Group/project schema and setup
│   │   ├── workspaces/          # Niri workspace registry
│   │   ├── ptt/                 # Push-to-talk dictation
│   │   ├── tailnets/            # Userspace tailscaled per tailnet
│   │   └── …                    # agents, claude-code, claude-usage, docs, opencode, …
│   │
│   └── darwin/                  # nix-darwin modules (options: features.darwin.*)
│
├── hosts/
│   ├── pc/                      # x86_64 template — start here
│   └── live/                    # aarch64 template
│
└── iso/                         # Installer image
    ├── default.nix              # image settings + the flake bundled at /iso/flute
    ├── live-features.nix        # the live system's OWN feature set (not a host's)
    ├── live-session.nix         # autologin
    └── install-script.nix       # flute-install
```

### How it fits together

- `features/` declares options. Every module is option-driven:
  `features.<group>.<name>.enable` turns it on, data fields are `mkOption`.
- A configuration *writes values* into those options. Yours does that from your
  own repository; the templates under `hosts/` do it here, and are the worked
  examples.
- `personalRoot` is an optional `specialArg`. Point it at your repository and the
  two features that auto-discover directories — projects and sessions — read
  `projects/<group>/` and `sessions/` from there. Unset, it is `null` and they do
  nothing.
- The installer image is built from this flake alone, never from a host, so two
  people building the same commit get the same image.

`./check-distributable.sh` evaluates the **full** system closure of every output
— both templates and both images. It is cheap, and a shallow attribute would not
reach the home-manager modules, which is where breakage hides. Run it after
touching anything under `features/`.

### Secrets

Two rules, and they are not stylistic — `/nix/store` is world-readable:

1. Never read a secret at evaluation time (`builtins.readFile`): the contents end
   up in the store and in the derivation hash.
2. Never address a secret as a Nix path (`./key`, `types.path`): the file is
   copied into the store, and a `toString ./x` inside a flake drags the whole
   flake tree in with it.

So secret-bearing options are `types.str` absolute paths, resolved on the running
machine at activation or runtime. Worked examples:
`features.fluteos.ptt.stt.apiKeyFile` (systemd `LoadCredential` paired with an
empty `SetCredential`, so a missing key still lets the unit start),
`features.fluteos.projects.secretsRoot`, and
`features.fluteos.claude-code.mcpServers.<name>.secrets`.

A missing secret is a warning and a degraded feature, never a failed build — a
machine that has not been given its keys yet must still activate.

### Using FluteOS without forking it

The flake exports the OS as a module set, so your configuration can live in your
own repository and keep nothing of ours:

```nix
{
  inputs.fluteos.url = "github:jiva-studio/flute-os";

  outputs = { fluteos, ... }: {
    nixosConfigurations.mine = fluteos.inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ fluteos.nixosModules.fluteos ./hosts/mine ];
    };
  };
}
```

`nixosModules.fluteos` carries every feature module plus the home-manager and
disko wiring, and nothing personal. `darwinModules.fluteos` is the nix-darwin
equivalent. Your host module needs at least:

```nix
{
  features.base.system.enable = true;        # required — declares the primary user
  features.base.system.hostname = "mine";
  features.profiles.desktop = true;
}
```

Build with `nixos-rebuild switch --flake ~/my-config#mine`; update the OS with
`nix flake update fluteos`. While developing against a local checkout,
`--override-input fluteos path:/path/to/fluteos` bypasses the lock so uncommitted
changes are picked up — note that a relative `path:../fluteos` input only works
while both trees are inside one repository.

To use the project/workspace and session features from your own repository, hand
it your own directory as `personalRoot` — that is the path the auto-discovery
reads, and it defaults to null (features off) when unset:

```nix
nixosConfigurations.mine = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  specialArgs = { personalRoot = ./.; };   # your repo, not ours
  modules = [ fluteos.nixosModules.fluteos ./hosts/mine ];
};
```

Then `projects/<group>/default.nix` and `sessions/` in *your* repo are picked up
automatically. Point `features.fluteos.projects.secretsRoot` at wherever your
checkout keeps credentials.

This is the arrangement the author uses, and the reason this repository has no
`personal/` directory: the private configuration is its own repo, and the two are
checked out side by side so `--override-input` can point at the local tree.

### Or fork it

If you would rather have one repository:

1. Copy `hosts/pc/` to `hosts/<yourmachine>/` and edit it. `hardware.nix` is
   regenerated by the installer; `disko.nix` is optional if you partition
   yourself.
2. Add it to `flake.nix` → `nixosConfigurations`.
3. Set `features.base.system.user.*` for yourself, and the `*ApiKeyFile` options
   for the features you use.
4. `nixos-rebuild switch --flake .#<yourmachine>`

`hosts/pc/` and `hosts/live/` are the worked examples. Keep them building —
`./check-distributable.sh` is how you find out that you did not.

## Rebuilding

```bash
./build.sh pc                            # or any host name
sudo nixos-rebuild switch --flake .#pc   # equivalent, done by hand
```

## Building the installer

```bash
./build-iso.sh          # this machine's architecture
./build-iso.sh x86      # x86_64 explicitly
./build-iso.sh arm      # aarch64 explicitly
```

The script detects the architecture, installs Nix if it is missing, adds swap on
a low-memory builder, and writes `fluteos-<arch>.iso` next to itself.

## Installation

### 1. Write the image and boot

```bash
sudo dd if=fluteos-x86_64.iso of=/dev/sdX bs=4M status=progress
```

Boot from it (`F12` / `F2` / `Del` during startup).

### 2. Log in

The live session logs in automatically. If it asks:

- **Username:** `user`
- **Password:** `qwerty`

Both are throwaway — the live system keeps no state. Open a terminal with
`MOD + Enter`, or press `MOD + Space` for the menu.

### 3. Install

```bash
lsblk                          # find your disk
sudo flute-install /dev/sda    # ERASES that disk
```

With no second argument it installs the template the image was built for (`pc` on
x86_64, `live` on aarch64). Pass a name to pick another host bundled on the
image; `flute-install` lists them if you name one it does not have.

It partitions with disko, copies the flake to `/mnt/etc/nixos`, generates
`hardware.nix` for the machine it detects, and runs `nixos-install`.

### 4. Set the password

The installed system's first-boot password is whatever its host declares —
`changeme` for the bundled templates.

```bash
sudo nixos-enter --root /mnt -c 'passwd user'
```

### 5. Reboot

```bash
reboot
```

## Keybindings

**MOD** = `Alt` by default, set per host with `features.base.niri.modKey`.

Bindings marked ▪ appear only when the feature behind them is enabled, so a
machine without that feature has no key that does nothing.

### Windows and columns

| Keys | Action |
|------|--------|
| `MOD + Space` | which-key menu |
| `MOD + Enter` | Terminal in the current workspace |
| `MOD + G` | Agent prompt |
| `MOD + Q` | Close window |
| `MOD + F` | Maximize column |
| `MOD + Shift + F` | Fullscreen |
| `MOD + Ctrl + F` | Expand column to available width |
| `MOD + R` | Cycle preset column widths |
| `MOD + Shift + R` | Cycle preset window heights |
| `MOD + C` | Center column |
| `MOD + W` | Tabbed column display |
| `MOD + ←/→` | Focus column (or monitor) left/right |
| `MOD + ↑/↓` | Focus window (or workspace) up/down |
| `MOD + Shift + ←/→` | Move column left/right (or to next monitor) |
| `MOD + Shift + ↑/↓` | Move window up/down (or to next workspace) |
| `MOD + [` | Consume window into column |
| `MOD + ]` | Expel window from column |
| `MOD + -` / `MOD + =` | Narrow / widen column |
| `MOD + Shift + -` / `MOD + Shift + =` | Shorten / heighten window |

### Workspaces, monitors, tags

| Keys | Action |
|------|--------|
| `Ctrl + Alt + 1…0` | Focus workspace 1–10 |
| `Ctrl + Alt + Shift + 1…0` | Move window to workspace 1–10 |
| `MOD + Ctrl + ↑/↓` | Raise / lower this workspace in the stack |
| `MOD + N` / `MOD + M` | Focus monitor left / right |
| `MOD + Shift + N` / `MOD + Shift + M` | Move column to monitor left / right |
| `MOD + O` | Overview |
| `MOD + ,` | Rename this workspace |
| `Alt + 1…4` | Focus the window tagged 1–4 |
| `Alt + Shift + 1…4` | Tag this window 1–4 |

### Everything else

| Keys | Action |
|------|--------|
| `Print` | Screenshot area |
| `Shift + Print` | Screenshot screen |
| `MOD + Print` | Screenshot window |
| `MOD + B` ▪ | Toggle the bar |
| `MOD + V` ▪ | Cycle push-to-talk dictation mode |
| `MOD + .` ▪ | Emoji picker |
| `MOD + Ctrl + L` ▪ | Lock screen |
| `MOD + Shift + E` | Quit niri |
| `XF86Audio{Raise,Lower}Volume`, `XF86AudioMute` | Volume |
| `XF86MonBrightness{Up,Down}` | Brightness |
| `XF86Audio{Play,Next,Prev,Stop}` ▪ | MPD transport |

`Alt + Tab` and `Alt + \`` are deliberately bound to nothing, so the muscle
memory of a floating window manager does not fight the tiling one.

Terminal keys are WezTerm's own defaults; FluteOS does not rebind them.

## Configurations

| Name | Architecture | What it is |
|------|--------------|------------|
| `pc` | x86_64-linux | Distributable template — the x86_64 starting point |
| `live` | aarch64-linux | Distributable template for ARM |
| `iso` | x86_64-linux | Installer image, offers `pc` |
| `iso-arm` | aarch64-linux | Installer image, offers `live` |

That is the whole list — a real machine is a host in your own repository, not an
entry here.

## License

MIT
