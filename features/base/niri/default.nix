# Niri Window Manager - compositor, keybindings, layout, session management
# Combines system-level config (compositor, fonts, portals)
# with home-manager config (KDL config file, workspaces, sessions, idle)
{ lib, config, pkgs, ... }:

let
  cfg = config.features.base.niri;
  theme = config.features.fluteos.theme.resolved;
  c = theme.helpers.c;

  # Captured out here because `config` is shadowed by the home-manager config
  # inside the HM block below. Keybindings that spawn a terminal ask the terminal
  # feature which one to use instead of naming it.
  osFeatures = config.features;

  # Import library helpers
  niriRules = import ./window-rule-helpers.nix { inherit theme c; };

  # Import KDL config generators (these return strings, not modules)
  inputConfig = import ./input.nix { inherit lib; modKey = cfg.modKey; keyboard = cfg.keyboard; };
  layoutConfig = import ./layout.nix { inherit theme c; };
  windowRulesConfig = import ./window-rules.nix { inherit theme c niriRules; };
in
{
  imports = [
    ./workspaces.nix
    ./tags.nix
    ./idle.nix
    ./session.nix
    ./session-restore.nix
    ./xwayland.nix
  ];

  options.features.base.niri = {
    enable = lib.mkEnableOption "Niri window manager";
    modKey = lib.mkOption {
      type = lib.types.str;
      default = "Alt";
      description = "Modifier key for niri keybindings";
    };
    extraBinds = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = ''
        Mod+Shift+S { spawn "my-screenshot-tool"; }
      '';
      description = ''
        Extra niri `binds` entries, in KDL, appended to the product's set. Lets a
        host add or override a binding without forking the module — niri takes
        the last definition for a key, so repeating one here replaces it.
      '';
    };

    extraWindowRules = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = ''
        window-rule {
            match app-id="com.example.Thing"
            open-floating true
        }
      '';
      description = ''
        Extra niri `window-rule` blocks, in KDL, appended to the product's set.
        A feature that ships a window of its own says how it should be placed
        here, rather than the compositor's rule file having to know about every
        feature that might be switched on.
      '';
    };

    keyboard = {
      layout = lib.mkOption {
        type = lib.types.str;
        default = "us";
        example = "us,de";
        description = ''
          XKB layout(s). A comma-separated list gives several layouts that are
          switched with `keyboard.options` — set that too, or the extra layouts
          are unreachable.
        '';
      };
      variant = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "dvorak";
        description = "XKB variant; empty means the layout's default.";
      };
      options = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "grp:alt_shift_toggle";
        description = ''
          XKB options, e.g. the layout-switch binding. Empty by default: any
          choice here silently takes a shortcut away from applications, so it
          belongs to the person using the machine, not to the distribution.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # --- System-level config (from modules/niri.nix) ---

    # Niri compositor
    programs.niri.enable = true;

    # ydotool for keyboard input injection (voxinput)
    programs.ydotool.enable = true;
    hardware.uinput.enable = true;
    services.udev.extraRules = ''
      KERNEL=="uinput", GROUP="input", MODE="0660"
    '';

    environment.systemPackages = with pkgs; [
      wl-clipboard
      bibata-cursors
      grim
      slurp
      wf-recorder
      brightnessctl
      pulsemixer
      imv
      libnotify
      voxinput
      dotool
      wtype
      fontconfig
      wlr-which-key
    ];

    # XDG Portal for Niri
    xdg.portal = {
      enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
        # Screencast on niri goes through the GNOME backend, which drives
        # niri's native org.gnome.Mutter.ScreenCast path (whole-output AND
        # per-window capture, restore tokens, plays well with browsers/Zoom).
        xdg-desktop-portal-gnome
        # xdg-desktop-portal-wlr is disabled on purpose: it's too flaky on
        # niri — whole-output only, and its PipeWire streams tend to deliver a
        # single frame and then freeze. We route ScreenCast to GNOME instead.
        # xdg-desktop-portal-wlr
      ];
      config = {
        common = {
          default = [ "gtk" ];
        };
        niri = {
          # Use the GNOME backend for capture; the wlr one is disabled above.
          "org.freedesktop.impl.portal.ScreenCast" = [ "gnome" ];
          "org.freedesktop.impl.portal.Screenshot" = [ "gnome" ];
          "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
        };
      };
    };

    # Polkit for authentication dialogs
    security.polkit.enable = true;

    # Fonts
    fonts = {
      enableDefaultPackages = true;
      packages = with pkgs; [
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
        jetbrains-mono
        nerd-fonts.jetbrains-mono
        literata
        lora
        merriweather
        crimson-pro
        eb-garamond
      ];
      fontconfig = {
        # From the theme, so the system's default fonts and the bar's are the
        # same decision made once.
        defaultFonts = {
          serif = [ theme.fonts.serif ];
          sansSerif = [ theme.fonts.sans ];
          monospace = [ theme.fonts.mono ];
        };
      };
    };

    # Environment variables for Wayland
    environment.sessionVariables = {
      XDG_CURRENT_DESKTOP = "niri";
      XDG_SESSION_TYPE = "wayland";
      XDG_SESSION_DESKTOP = "niri";
      MOZ_ENABLE_WAYLAND = "1";
      NIXOS_OZONE_WL = "1";
      ELECTRON_OZONE_PLATFORM_HINT = "wayland";
      QT_AUTO_SCREEN_SCALE_FACTOR = "1";
      QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    };

    # --- Home-manager config (niri KDL config + keybindings + startup) ---

    home-manager.users.${config.features.base.system.user.name} = { config, pkgs, ... }:
    let
      mod = cfg.modKey;
      keybindingsConfig = import ./keybindings.nix {
        inherit mod config theme lib osFeatures;
        extraBinds = cfg.extraBinds;
      };
      startupConfig = import ./startup.nix { inherit pkgs config; };

      niriConfig = ''
        ${inputConfig}
        ${layoutConfig}
        ${startupConfig}
        ${windowRulesConfig}
        ${cfg.extraWindowRules}
        ${keybindingsConfig}
      '';
    in
    {
      xdg.configFile."niri/config.kdl".text = niriConfig;
    };
  };
}
