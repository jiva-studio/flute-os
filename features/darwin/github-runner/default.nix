# GitHub Actions self-hosted runner for macOS, registered as a per-user
# LaunchAgent (NOT a system daemon) — required for iOS code-signing,
# Simulator, keychain, and other macOS APIs that need a user-session context.
#
# Mac prerequisite (one-time, manual): enable Auto Login for the runner user
# in System Settings → Users & Groups → Automatic Login → ${cfg.user}.
# Without auto-login, the runner only starts after someone logs in graphically.
{ lib, config, pkgs, ... }:
let
  cfg = config.features.darwin.github-runner;

  homeDir = "/Users/${cfg.user}";
  rootDir = "${homeDir}/.github-runner";

  # nixpkgs `github-runner` 2.333.1 dropped `safe_sleep.sh` from
  # $out/lib/github-runner/ while leaving the `$DIR/safe_sleep.sh` call inside
  # `run-helper.sh`. Any retry path inside the listener (registration replaced,
  # network blip, runner self-update) crashes with:
  #   .../lib/github-runner/safe_sleep.sh: No such file or directory
  # then loops, and GitHub eventually evicts the registration. Re-add it.
  # Verbatim copy of upstream actions/runner's src/Misc/layoutroot/safe_sleep.sh
  # — wall-clock-aware sleep so macOS App Nap / suspend doesn't overshoot.
  safeSleepScript = pkgs.writeShellScript "safe_sleep.sh" ''
    SLEEP_DURATION=$1
    NOW=$(date +%s)
    TARGET_TIME=$((NOW + SLEEP_DURATION))
    while [ $(date +%s) -lt $TARGET_TIME ]; do
        sleep 1
    done
  '';
  github-runner-patched = pkgs.github-runner.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      install -m 0755 ${safeSleepScript} $out/lib/github-runner/safe_sleep.sh
    '';
  });

  # Expand each runner config into N concrete instances.
  # Index suffix is zero-padded to the width of `count` so 1..12 → 01..12 —
  # makes runner names line up in `gh api` listings, launchctl output, and
  # `~/.github-runner/` directory entries regardless of count.
  expandRunners = name: rcfg:
    if rcfg.count == 1
    then [ (rcfg // { instanceName = name; }) ]
    else let
      width = builtins.stringLength (toString rcfg.count);
    in lib.genList (i: rcfg // {
      instanceName = "${name}-${lib.fixedWidthNumber width (i + 1)}";
    }) rcfg.count;

  instances = lib.concatLists (lib.mapAttrsToList expandRunners cfg.runners);

  runnerScript = pkgs.writeShellApplication {
    name = "github-runner-loop";
    runtimeInputs = (with pkgs; [ bash coreutils curl jq git nodejs ]) ++ [ github-runner-patched ];
    text = builtins.readFile ./run.sh;
  };

  mkAgent = inst: lib.nameValuePair "github-runner-${inst.instanceName}" {
    serviceConfig = {
      Label = "org.nixos.github-runner.${inst.instanceName}";
      ProgramArguments = [
        "${runnerScript}/bin/github-runner-loop"
        inst.instanceName
        inst.url
        "${rootDir}/${inst.instanceName}.pat"
        (lib.concatStringsSep "," inst.labels)
      ];
      KeepAlive = true;
      RunAtLoad = true;
      WorkingDirectory = "${rootDir}/${inst.instanceName}";
      StandardOutPath = "${rootDir}/${inst.instanceName}/runner.log";
      StandardErrorPath = "${rootDir}/${inst.instanceName}/runner.err";
      EnvironmentVariables = {
        # pkgs.github-runner defaults RUNNER_ROOT to $HOME/.github-runner —
        # ONE path shared by all instances, which means .runner/.credentials*
        # files race and overwrite each other. Pin it per-instance so each
        # runner has its own registration state and bin/externals stage dir.
        RUNNER_ROOT = "${rootDir}/${inst.instanceName}";
        # nix store paths first; then nix-darwin sw path; then macOS system
        # paths (so /usr/bin/tar — BSD tar — wins over any gnutar; actions/cache
        # rejects GNU tar's flag combinations). Provide `gtar` separately as
        # a shim so actions/upload-pages-artifact (which calls `gtar` by name)
        # finds it without exposing the GNU `tar` binary.
        PATH = (lib.makeBinPath ((with pkgs; [
          bash coreutils gzip unzip curl jq git nodejs
          (writeShellScriptBin "gtar" ''exec ${gnutar}/bin/tar "$@"'')
        ]) ++ [ github-runner-patched ])) + ":/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        # HOME inherited from user-agent context = /Users/${cfg.user}.
        # Don't override — Xcode, security, codesign, simctl all read HOME
        # from getpwnam, so it must match the launchd env value.
        # Shared across all instances — beneficial for warm caches; ephemeral
        # _work/ checkouts stay isolated via WorkingDirectory above.
        RUNNER_TOOL_CACHE = "${rootDir}/_tool-cache";
        ANDROID_SDK_ROOT = "${rootDir}/_android-sdk";
        # fastlane warns under C locale and sh-actions can break on non-ASCII paths.
        LANG = "en_US.UTF-8";
        LC_ALL = "en_US.UTF-8";
      };
    };
  };

  installSecret = inst: ''
    install -d -m 700 -o ${cfg.user} -g staff ${rootDir}
    install -d -m 700 -o ${cfg.user} -g staff ${rootDir}/${inst.instanceName}
    install -m 600 -o ${cfg.user} -g staff \
      ${inst.patSource} ${rootDir}/${inst.instanceName}.pat
  '';

  installShared = ''
    install -d -m 755 -o ${cfg.user} -g staff ${rootDir}/_tool-cache
    install -d -m 755 -o ${cfg.user} -g staff ${rootDir}/_android-sdk
    # ruby/setup-ruby@v1 hard-codes /Users/runner/hostedtoolcache/Ruby/...
    # (Ruby binaries have that path baked in via RPATH, no env override possible).
    # Symlink to the runner user's home so setup-ruby can write inside.
    # Use `ln -sfn` so an old symlink (e.g. left over from the legacy
    # /var/lib/github-runner daemon layout) gets atomically retargeted —
    # a plain `ln -s` no-ops on existing symlinks and leaves them stale.
    ln -sfn ${homeDir} /Users/runner
    # Apple WWDR Intermediate Certificate (G3) — required for codesign to build
    # a trust chain from the user's Apple Distribution cert to Apple's root.
    # System keychain is the right place; activation runs as root so we have
    # write access. Idempotent.
    WWDR_TMP="$(/usr/bin/mktemp -t wwdr).cer"
    if /usr/bin/curl -fsSL https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer -o "$WWDR_TMP"; then
      /usr/bin/security import "$WWDR_TMP" -k /Library/Keychains/System.keychain -t cert 2>/dev/null || true
      /bin/rm -f "$WWDR_TMP"
    fi
  '';
in {
  options.features.darwin.github-runner = {
    enable = lib.mkEnableOption "GitHub Actions self-hosted runner (macOS LaunchAgent)";

    user = lib.mkOption {
      type = lib.types.str;
      example = "akd";
      description = ''
        User account whose login session runs the runner. iOS code-signing,
        Simulator, and keychain operations require a real user-session context
        (i.e. LaunchAgent, not LaunchDaemon). Enable Auto Login for this user
        in System Settings → Users & Groups → Automatic Login so the runner
        starts at boot without manual intervention. Required (no default) —
        host explicitly states which account runs the runner.
      '';
    };

    runners = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          url = lib.mkOption {
            type = lib.types.str;
            example = "https://github.com/your-org";
            description = "Org URL (https://github.com/<org>) or repo URL (https://github.com/<owner>/<repo>).";
          };
          patSource = lib.mkOption {
            type = lib.types.path;
            description = ''
              Path to a file containing a GitHub Personal Access Token with
              `admin:org` scope (org-level runners) or `repo` scope (repo-level).
              Installed under the runner user's home with mode 600 at activation.
              Recommended: store as a `*.secret` file in the repo (git-crypt
              encrypts it via the .gitattributes filter).
            '';
          };
          labels = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "self-hosted" "macos" ];
            description = "Labels added to this runner.";
          };
          count = lib.mkOption {
            type = lib.types.ints.positive;
            default = 1;
            description = ''
              Parallel ephemeral runner instances under this name. Each gets
              its own LaunchAgent and workspace, so GitHub can dispatch up to N
              jobs concurrently. 3-5 reasonable on a 16-24 GiB M-series mac.
            '';
          };
        };
      });
    };
  };

  config = lib.mkIf cfg.enable {
    system.activationScripts.extraActivation.text = lib.mkAfter (
      installShared + "\n" +
      lib.concatStringsSep "\n" (map installSecret instances)
    );

    launchd.user.agents = lib.listToAttrs (map mkAgent instances);

    environment.systemPackages = [
      github-runner-patched
      runnerScript
    ] ++ (with pkgs; [
      # CI/iOS build tooling — only the runner host needs these (moved here from
      # features/darwin/system so non-CI Macs stay lean).
      #
      # Required by shlokas .github/workflows/storage-sync.yml on the runner
      # (replaces the upstream `curl | sudo bash` install — github-runner
      # has no passwordless sudo on macOS).
      rclone
      # iOS build/deploy: nix-managed Ruby is linked against an OpenSSL that
      # parses ES256 .p8 keys correctly. ruby/setup-ruby@v1's Ruby on macOS
      # errors with "invalid curve name" on the App Store Connect API key.
      ruby_3_3
      bundler
      cocoapods
    ]);
  };
}
