# FluteOS — a declarative NixOS distribution with Niri.
#
# This is the PRODUCT: feature modules, host templates and the installer image.
# It contains no personal configuration of any kind, which is the property that
# makes it distributable — and now a structural one rather than a promise, since
# the owner's own configuration lives in a separate private repository that
# consumes this flake.
#
# Architecture:
# - features/base/     → NixOS/home-manager wrappers   (options: features.base.*)
# - features/fluteos/  → FluteOS tools and widgets     (options: features.fluteos.*)
# - features/darwin/   → nix-darwin modules            (options: features.darwin.*)
# - features/profiles/ → bundles of features that travel together
# - hosts/             → distributable host templates (pc x86_64, live aarch64)
# - iso/               → the installer image, built from this flake alone
#
# Consume it from your own repository rather than forking — see README.md:
#
#   inputs.fluteos.url = "github:jiva-studio/flute-os";
#   …
#   nixosSystem { modules = [ fluteos.nixosModules.fluteos ./hosts/mine ]; }
#
# Build commands:
#   nixos-rebuild switch --flake .#pc   # the x86_64 template
#   nix build .#iso                     # x86_64 installer ISO
#   nix build .#iso-arm                 # aarch64 installer ISO
#   ./check-distributable.sh            # every output still evaluates
{
  description = "Flute OS - Declarative NixOS distribution with Niri";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    lazyvim-nix = {
      url = "github:pfassina/lazyvim-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin.url = "github:catppuccin/nix";

    nur.url = "github:nix-community/NUR";

    nix-flatpak.url = "github:gmodena/nix-flatpak";

    nix-darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, disko, home-manager, nixos-hardware, lazyvim-nix, catppuccin, nur, nix-flatpak, nix-darwin, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];

      flake = let
        lib = nixpkgs.lib;

        featureModules = [
          ./features/profiles
          ./features/fluteos/theme
          # Base features
          ./features/base/system
          ./features/base/certificates
          ./features/base/bluetooth
          ./features/base/wifi
          ./features/base/audio
          ./features/base/webcam
          ./features/base/docker
          ./features/base/ssh
          ./features/base/greetd
          ./features/base/nas
          ./features/base/iphone
          ./features/base/automount
          ./features/base/performance
          ./features/base/niri
          ./features/base/terminal
          ./features/base/shell
          ./features/base/neovim
          ./features/base/git
          ./features/base/mako
          ./features/base/emoji
          ./features/base/gtk
          ./features/base/qt
          ./features/base/swaylock
          ./features/base/screencast
          ./features/base/zoom
          ./features/base/obsidian
          ./features/base/firefox
          ./features/base/yazi
          ./features/base/nautilus
          ./features/base/zathura
          ./features/base/foliate
          ./features/base/digikam
          ./features/base/mpd
          ./features/base/onepassword
          ./features/base/telegram
          ./features/base/teams
          ./features/base/android
          ./features/base/tailscale

          # FluteOS features
          ./features/fluteos/apps
          ./features/fluteos/weather
          ./features/fluteos/which-key
          ./features/fluteos/ptt
          ./features/fluteos/claude-code
          ./features/fluteos/claude-usage
          ./features/fluteos/opencode
          ./features/fluteos/wallpapers
          ./features/fluteos/sessions
          ./features/fluteos/projects
          ./features/fluteos/workspaces
          ./features/fluteos/agents
          ./features/fluteos/docs
          ./features/fluteos/agent-context
          ./features/fluteos/waybar
          ./features/fluteos/tailnets
        ];

        # Darwin-only feature modules (loaded only into darwinConfigurations).
        # Generic only: a module that orchestrates private software belongs in the
        # configuration that owns that software, not here.
        darwinFeatureModules = [
          ./features/darwin/system
          # github-runner: CI no longer used — module + kartala's enable block
          # commented out together so eval stays valid. Re-enable both to restore.
          # ./features/darwin/github-runner
          ./features/darwin/tailscale
          ./features/darwin/vector-backend
        ];

        # FluteOS itself: every feature module plus the home-manager/disko wiring
        # they depend on. This is exactly what `nixosModules.fluteos` exports.
        osModules = [
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          ({ config, ... }: {
            # Supplied here, not expected from the consumer's specialArgs.
            # features/base/neovim takes `lazyvim-nix` as a module argument, so
            # `nixosModules.fluteos` did not evaluate on its own — a downstream
            # config following the README got "attribute 'lazyvim-nix' missing"
            # from a module it had never heard of. The flake owns that input; it
            # should hand it over.
            _module.args.lazyvim-nix = lazyvim-nix;

            # Where to auto-discover project and session directories. A consumer
            # points this at its own tree by passing `personalRoot` in
            # specialArgs, which takes precedence; null means those two features
            # find nothing and do nothing.
            #
            # It has to be declared here even though features/fluteos/{projects,
            # sessions} both write `personalRoot ? null` in their signatures: the
            # module system does not use a function's own default for a module
            # argument — it looks the name up in `_module.args` and fails if it is
            # absent. So `nixosModules.fluteos` on its own died with "attribute
            # 'personalRoot' missing".
            _module.args.personalRoot = lib.mkDefault null;

            nixpkgs.overlays = [
              nur.overlays.default
            ];
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            # Back up (not clobber) any pre-existing unmanaged dotfiles on
            # activation — e.g. a stale ~/.mozilla/firefox/profiles.ini.
            home-manager.backupFileExtension = "hmbak";
            home-manager.users.${config.features.base.system.user.name} = {
              imports = [
                catppuccin.homeModules.catppuccin
                nix-flatpak.homeManagerModules.nix-flatpak
              ];
            };
            # Pass the resolved theme into home-manager modules. NixOS-side
            # modules read it directly via config.features.fluteos.theme.resolved.
            home-manager.extraSpecialArgs = {
              theme = config.features.fluteos.theme.resolved;
              inherit lazyvim-nix;
            };
          })
        ] ++ featureModules;

        # disko.nix is optional: a host that does not manage its own partitioning
        # (a consumer's laptop, an example template) should not be forced to ship
        # one just to evaluate.
        hostModules = hostDir:
          [ (hostDir + "/default.nix") ]
          ++ lib.optional (builtins.pathExists (hostDir + "/disko.nix")) (hostDir + "/disko.nix");

        # This repo's own hosts are the distributable templates under hosts/.
        # There is no personal/ fallback any more: a private configuration is a
        # separate flake that imports nixosModules.fluteos and supplies its own
        # host directory.
        mkSystem = hostName: system: extraModules:
          let hostDir = ./hosts + "/${hostName}"; in
          nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = { inherit inputs hostName; };
            modules = osModules ++ hostModules hostDir ++ extraModules;
          };

        # Helper to create an installer ISO.
        #
        # `osModules` and no host directory at all: the image is the product and
        # nothing else. It used to be built from a host, which composed that
        # machine's account, timezone, tailnets and widgets into the image every
        # downloader would boot.
        #
        # The live system's own feature set lives in iso/live-features.nix.
        # `installTarget` is only the host `flute-install` offers by default; the
        # user can name any other host bundled on the image.
        mkISO = system: installTarget: extraModules:
          nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = {
              inherit inputs installTarget;
              hostName = "fluteos-live";
            };
            modules = osModules ++ [
              "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
              ./iso
            ] ++ extraModules;
          };

      in {
        # === FluteOS as a consumable module set ===
        #
        # Keep your own configuration in your own repository and import FluteOS
        # from it, instead of forking this one:
        #
        #   inputs.fluteos.url = "github:jiva-studio/flute-os";
        #   …
        #   nixosSystem {
        #     specialArgs = { personalRoot = ./.; };   # for projects/sessions
        #     modules = [ fluteos.nixosModules.fluteos ./hosts/mine ];
        #   }
        #
        # `personalRoot` is optional and defaults to null: the modules that
        # auto-discover project and session directories then simply do nothing.
        nixosModules = {
          fluteos = { imports = osModules; };
          default = self.nixosModules.fluteos;
        };
        darwinModules = {
          fluteos = { imports = darwinFeatureModules; };
          default = self.darwinModules.fluteos;
        };

        nixosConfigurations = {
          # Distributable templates — what a clean clone builds, and what the
          # installer images offer, one per architecture.
          pc = mkSystem "pc" "x86_64-linux" [];
          live = mkSystem "live" "aarch64-linux" [];

          # Installer ISOs. Product only — see mkISO.
          iso = mkISO "x86_64-linux" "pc" [];
          iso-arm = mkISO "aarch64-linux" "live" [];
        };

        # ISO packages. Named for what they are; `nix build .#` on either
        # architecture gives you that architecture's installer.
        packages.x86_64-linux = {
          iso = self.nixosConfigurations.iso.config.system.build.isoImage;
          default = self.packages.x86_64-linux.iso;
        };
        packages.aarch64-linux = {
          iso = self.nixosConfigurations.iso-arm.config.system.build.isoImage;
          default = self.packages.aarch64-linux.iso;
        };

        # Helper message for macOS
        packages.aarch64-darwin.default = builtins.throw ''
          ISO must be built on Linux. Use: orb -m ubuntu then ./build-iso.sh
        '';
        packages.x86_64-darwin.default = builtins.throw ''
          ISO must be built on Linux.
        '';
      };
    };
}
