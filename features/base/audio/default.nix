{ lib, config, ... }:
{
  options.features.base.audio = {
    enable = lib.mkEnableOption "Audio (PipeWire)";
  };

  config = lib.mkIf config.features.base.audio.enable {
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };
  };
}
