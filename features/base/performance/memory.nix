{ lib, config, ... }:
{
  config = lib.mkIf config.features.base.performance.enable {
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 50;
      priority = 100;
    };
    boot.kernel.sysctl = {
      "vm.swappiness" = 180;
      "vm.watermark_boost_factor" = 0;
      "vm.watermark_scale_factor" = 125;
      "vm.page-cluster" = 0;
      "vm.vfs_cache_pressure" = 50;
      "vm.compaction_proactiveness" = 0;
      "vm.min_free_kbytes" = 65536;
    };
    systemd.tmpfiles.rules = [
      "w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise"
      "w /sys/kernel/mm/transparent_hugepage/defrag - - - - defer+madvise"
    ];
  };
}
