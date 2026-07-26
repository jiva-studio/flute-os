{ lib, config, ... }:
let theme = config.features.fluteos.theme.resolved; in
{
  options.features.base.emoji = {
    enable = lib.mkEnableOption "Emoji picker (bemoji)";
  };

  config = lib.mkIf config.features.base.emoji.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, ... }: let
      emoji = pkgs.writeShellScriptBin "emoji" ''
        export BEMOJI_PICKER_CMD="${pkgs.fuzzel}/bin/fuzzel -d \
          --width=40 \
          --lines=10 \
          --horizontal-pad=8 \
          --vertical-pad=6 \
          --inner-pad=4 \
          --background=${theme.fuzzel.bg} \
          --text-color=${theme.fuzzel.fg} \
          --selection-color=${theme.fuzzel.selBg} \
          --selection-text-color=${theme.fuzzel.selFg} \
          --border-color=${theme.fuzzel.border} \
          --border-width=${toString theme.fuzzel.borderWidth} \
          --border-radius=${toString theme.fuzzel.borderRadius} \
          --font='${theme.fuzzel.font}'"
        export BEMOJI_CLIP_CMD="${pkgs.wl-clipboard}/bin/wl-copy"
        ${pkgs.bemoji}/bin/bemoji -e | tr -d '\n' | ${pkgs.wl-clipboard}/bin/wl-copy && sleep 0.05 && ${pkgs.wtype}/bin/wtype -M ctrl v -m ctrl
      '';
    in {
      home.packages = [ emoji ];
    };
  };
}
