{ lib, config, ... }:
{
  imports = [ ./wezterm ];

  options.features.base.terminal = {
    enable = lib.mkEnableOption "Terminal emulator (WezTerm)";

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

    accentPaneTitle = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "Orchestrator";
      description = ''
        Pane title that gets a translucent accent wash over the WezTerm
        background, so that one window is findable among otherwise identical
        ones. The title is the one set through OSC 1337 `tab_title` — i.e. what
        the fish `set-tab-title` helper writes — and the match is exact.

        Empty (the default) disables the tint: which window deserves to be
        special is a workflow decision, not something the distribution knows.
      '';
    };
  };
}
