{ lib, config, pkgs, ... }:

let
  cfg = config.features.base.performance;
in
{
  imports = [
    ./io.nix
    ./memory.nix
    ./scheduler.nix
  ];

  options.features.base.performance = {
    enable = lib.mkEnableOption "Performance optimizations";
    turboBoost = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable battery-aware laptop tuning: TLP-driven AC/BAT switching,
        EPP=power on battery, boost off on battery, aggressive PCIe ASPM,
        deep S3 sleep, zswap. Hardware-agnostic — works on any cpufreq
        driver. Vendor-specific knobs (amdgpu/intel-pstate, GPU env vars)
        belong in the host's own performance module.
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf cfg.turboBoost {
      boot.kernelParams = [
        "nowatchdog"
        "nmi_watchdog=0"
        "pcie_aspm=force"
        # S3 instead of s2idle — meaningfully lower drain in suspend.
        "mem_sleep_default=deep"
        "zswap.enabled=1"
        "zswap.compressor=zstd"
        "zswap.max_pool_percent=20"
      ];

      boot.kernel.sysctl = {
        "kernel.sched_autogroup_enabled" = 1;
      };

      # TLP and power-profiles-daemon both manage CPU/platform power and conflict.
      services.power-profiles-daemon.enable = lib.mkForce false;
      services.tlp = {
        enable = true;
        settings = {
          CPU_SCALING_GOVERNOR_ON_AC  = "powersave";
          CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

          CPU_ENERGY_PERF_POLICY_ON_AC  = "balance_performance";
          CPU_ENERGY_PERF_POLICY_ON_BAT = "power";

          # Disabling boost on battery is the single largest battery-life win
          # on modern laptop CPUs (both Zen and modern Intel).
          CPU_BOOST_ON_AC  = 1;
          CPU_BOOST_ON_BAT = 0;

          PLATFORM_PROFILE_ON_AC  = "balanced";
          PLATFORM_PROFILE_ON_BAT = "low-power";

          RUNTIME_PM_ON_AC  = "auto";
          RUNTIME_PM_ON_BAT = "auto";

          PCIE_ASPM_ON_AC  = "default";
          PCIE_ASPM_ON_BAT = "powersupersave";

          WIFI_PWR_ON_AC  = "off";
          WIFI_PWR_ON_BAT = "on";

          USB_AUTOSUSPEND = 1;
        };
      };

      # On a laptop irqbalance just spreads wakeups across cores that would
      # otherwise stay parked; net negative for idle power.
      services.irqbalance.enable = false;

      # Generic perf/battery diagnostics. powertop works on any platform;
      # sysbench + stress-ng give reproducible benches.
      environment.systemPackages = with pkgs; [
        powertop
        sysbench
        stress-ng
      ];
    })
  ]);
}
