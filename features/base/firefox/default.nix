# Firefox: the browser the distribution ships.
#
# This file is the product surface. It declares *what* can be configured about
# the browser and picks defaults a stranger can live with; it encodes no taste.
# In particular the extension set, the theme, the toolbar layout, the tab-bar
# tricks, the bookmarks and the new-tab tiles are all options with neutral
# defaults — the owner's versions of them live in personal/.
#
# Shape of the config:
#   profile-config.nix          — the shape shared by every profile
#   default-profile-config.nix  — extra shape for the one default profile
# Both are plain functions of (lib, cfg): they read options, never config.
{ lib, config, pkgs, ... }:

let
  cfg = config.features.base.firefox;
  addons = pkgs.nur.repos.rycee.firefox-addons;

  pinnedSiteType = lib.types.submodule {
    options = {
      url = lib.mkOption {
        type = lib.types.str;
        example = "https://nixos.org";
        description = "Address the tile opens.";
      };
      label = lib.mkOption {
        type = lib.types.str;
        example = "NixOS";
        description = "Text shown under the tile.";
      };
    };
  };
in
{
  options.features.base.firefox = {
    enable = lib.mkEnableOption "Firefox browser";

    extensions = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ addons.ublock-origin ];
      defaultText = lib.literalExpression "[ pkgs.nur.repos.rycee.firefox-addons.ublock-origin ]";
      example = lib.literalExpression ''
        with pkgs.nur.repos.rycee.firefox-addons; [
          ublock-origin
          onepassword-password-manager
        ]
      '';
      description = ''
        Extensions installed into every profile (the default profile and each
        per-group profile), taken from the rycee firefox-addons set.

        The default is uBlock Origin and nothing else: an ad/tracker blocker is
        defensible for everybody, while a password manager, a theme, a keyboard
        layer or a YouTube segment skipper are personal choices that a
        distribution has no business making for its users. Add yours in your own
        configuration.
      '';
    };

    activeThemeID = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "{76aabc99-c1a8-4c1e-832b-d4f2941d5a7a}";
      description = ''
        Internal GUID of the theme add-on to activate, or null to leave Firefox
        on its own default theme.

        The GUID is the add-on's own identifier, not something derivable from the
        package name, so it has to be stated by whoever chose the theme — and it
        must belong to an add-on listed in `extensions`, otherwise Firefox falls
        back to the default theme.
      '';
    };

    uiCustomizationState = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = lib.literalExpression ''builtins.toJSON { placements = { … }; currentVersion = 20; }'';
      description = ''
        Verbatim value for `browser.uiCustomization.state`: which button sits on
        which toolbar. Null (the default) leaves Firefox to place things itself.

        Deliberately an opaque string rather than something generated from
        `extensions`. The blob addresses extension buttons by per-add-on internal
        widget ids (`ublock0_raymondhill_net-browser-action`,
        `_3c078156-…_-browser-action`) which no Nix package attribute exposes;
        any "generator" would really be a hardcoded id table that goes silently
        wrong for every add-on missing from it. A toolbar layout is also a
        personal arrangement, so it belongs in the same place as the rest of
        one's taste. Keep it in sync with `extensions` by hand: ids of add-ons
        that are not installed are simply ignored by Firefox.
      '';
    };

    chrome = {
      hideTabBar = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Collapse the tab strip and flatten the titlebar, for people who
          navigate tabs through a sidebar extension instead.

          False by default, and that matters: a browser with no visible tabs and
          no explanation is indistinguishable from a broken browser, and nothing
          in the UI hints at how to get them back.
        '';
      };

      autoHideNavbar = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Slide the navigation toolbar (address bar, buttons) out of view until
          the pointer or keyboard focus reaches the top of the window. Off by
          default: the address bar is how a user knows where they are.
        '';
      };

      extraCss = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = ''
          Extra `userChrome.css` appended to whatever the options above
          generate, for tweaks the distribution does not model. Empty by
          default; empty also means no `userChrome.css` file is written at all
          when both switches above are off.
        '';
      };
    };

    defaultProfile = {
      bookmarks = lib.mkOption {
        type = lib.types.listOf lib.types.attrs;
        default = [ ];
        example = lib.literalExpression ''
          [
            {
              name = "Bookmarks Toolbar";
              toolbar = true;
              bookmarks = [ { name = "NixOS"; url = "https://nixos.org"; } ];
            }
          ]
        '';
        description = ''
          Declarative bookmark tree for the default profile, in the shape
          home-manager's `programs.firefox.profiles.<p>.bookmarks.settings`
          expects. Empty by default, which leaves the user's own bookmarks
          entirely alone — managing this list replaces them wholesale, so the
          distribution ships nothing here.

          A non-empty list additionally requires `bookmarksForce = true`; see
          that option.
        '';
      };

      bookmarksForce = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Acknowledge that managing `bookmarks` destroys the bookmarks already
          in the profile. False by default: overwriting somebody's bookmarks is
          not something an operating system may do quietly, so the person whose
          bookmarks they are has to say this word out loud. With `bookmarks`
          non-empty and this false, the build fails with home-manager's own
          explanation instead of eating the data.
        '';
      };

      pinnedSites = lib.mkOption {
        type = lib.types.listOf pinnedSiteType;
        default = [ ];
        example = lib.literalExpression ''
          [
            { url = "https://nixos.org"; label = "NixOS"; }
          ]
        '';
        description = ''
          Tiles pinned to the new-tab page's Shortcuts row. Empty by default —
          which sites someone wants one click away is the definition of personal
          — and then the row just fills itself from the user's own history.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable (let
    userName = config.features.base.system.user.name;
  in {
    home-manager.users.${userName} = { config, pkgs, lib, ... }:
    let
      profileConfig = import ./profile-config.nix { inherit lib cfg; };
      defaultProfileConfig = import ./default-profile-config.nix { inherit lib cfg; };

      mergeProfiles = base: override:
        lib.recursiveUpdate
          (lib.recursiveUpdate base override)
          {
            extensions.packages =
              (base.extensions.packages or []) ++
              (override.extensions.packages or []);
          };

      # Groups with a firefoxProfile defined → get their own profile.
      # Falls back to {} when fluteos.projects feature is not enabled (e.g. live ISO).
      groupsWithProfiles = lib.filterAttrs
        (_: g: g.firefoxProfile != null)
        (config.features.fluteos.projects.groups or {});

      # Ordered by optional firefoxProfile.order (lower first), then by key.
      # Drives the profile `id` → the order profiles appear in Firefox.
      groupKeys =
        let ord = k: groupsWithProfiles.${k}.firefoxProfile.order or 999;
        in lib.sort
          (a: b: let oa = ord a; ob = ord b; in oa < ob || (oa == ob && a < b))
          (lib.attrNames groupsWithProfiles);

      # Build per-group profile entry. iconAssets is stripped before merge
      # (handled separately via home.file).
      # `extraCss` is APPENDED to the generated userChrome; anything else in
      # firefoxProfile replaces the matching field. Without it a group that wanted
      # one extra CSS rule had to restate the whole stylesheet — including the
      # hideTabBar and autoHideNavbar rules this module generates from options —
      # and then froze a copy of them that could never follow a product change.
      mkGroupProfile = idx: key:
        let
          g = groupsWithProfiles.${key};
          extras = removeAttrs g.firefoxProfile [ "iconAssets" "order" "extraCss" ];
          merged = mergeProfiles profileConfig extras;
          extraCss = g.firefoxProfile.extraCss or "";
        in
        {
          name = key;
          value = merged // {
            id = idx;
            name = g.displayName;
            isDefault = false;
          } // lib.optionalAttrs (extraCss != "") {
            userChrome = (merged.userChrome or "") + "\n" + extraCss;
          };
        };

      groupProfiles = lib.listToAttrs (lib.imap1 mkGroupProfile groupKeys);

      # Per-profile icon files: home.file.".mozilla/firefox/<key>/chrome/icons/<name>".source = path;
      iconFiles = lib.foldl' (acc: key:
        let
          g = groupsWithProfiles.${key};
          icons = g.firefoxProfile.iconAssets or {};
        in
        acc // (lib.mapAttrs' (iconName: src: {
          name = ".mozilla/firefox/${key}/chrome/icons/${iconName}";
          value.source = src;
        }) icons)
      ) {} groupKeys;
    in
    {
      home.file = iconFiles;

      # groupProfiles is merged over the default profile with `//`, so a group
      # keyed "default" would silently replace it and leave the browser without
      # a default profile. Say so instead.
      assertions = [
        {
          assertion = !(groupProfiles ? "default");
          message = ''
            features.fluteos.projects.groups.default declares a firefoxProfile,
            but "default" is the key of the browser's own default profile.
            Rename the group.
          '';
        }
      ];

      # Note: http/https MIME defaults are owned by features.fluteos.workspaces
      # (fluteos-workspace-browser.desktop), so links route to the workspace profile.

      programs.firefox = {
        enable = true;
        package = pkgs.firefox;
        # nixpkgs firefox sets MOZ_LEGACY_PROFILES=1, so the browser reads
        # profiles from ~/.mozilla/firefox. The HM module otherwise defaults to
        # the XDG path (~/.config/mozilla/firefox), which firefox would ignore.
        configPath = ".mozilla/firefox";
        profiles = {
          # The attribute key becomes the on-disk directory
          # (~/.mozilla/firefox/<key>). Keyed by login name rather than a literal
          # "default" on purpose: the key is derived from the user, so it carries
          # nothing personal into the product, and renaming it would strand every
          # existing profile directory — history, cookies and open sessions live
          # there, and profiles.ini is regenerated, so the old data would look
          # lost. The name Firefox displays comes from the option below.
          ${userName} = mergeProfiles profileConfig defaultProfileConfig // {
            id = 0;
            name = config.features.fluteos.projects.defaultBrowserProfile or "Default";
            isDefault = true;
          };
        } // groupProfiles;
      };
    };
  });
}
