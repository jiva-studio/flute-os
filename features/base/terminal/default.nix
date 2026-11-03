{ lib, config, ... }:
{
  imports = [ ./wezterm ];

  options.features.base.terminal = {
    enable = lib.mkEnableOption "Terminal emulator (WezTerm)";

    opacity = lib.mkOption {
      type = lib.types.numbers.between 0.0 1.0;
      default = 1.0;
      description = ''
        Window background opacity (1.0 = fully opaque).
      '';
    };

    spawnCommand = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "wezterm" "start" "--always-new-process" ];
      description = ''
        argv prefix that opens a new terminal window and runs the program given
        as the remaining arguments. Other features read this instead of naming a
        terminal, so replacing the terminal is one setting rather than an edit in
        every module that ever spawns one.

        --always-new-process keeps the spawned window independent of a running
        WezTerm GUI instead of becoming a tab inside it.
      '';
    };

    appIdFlag = lib.mkOption {
      type = lib.types.str;
      default = "--class";
      example = "--app-id";
      description = ''
        Flag the terminal uses to set a window's app-id / class, so window rules
        can target a spawned TUI. WezTerm and kitty use --class, foot uses
        --app-id.
      '';
    };
  };
}
