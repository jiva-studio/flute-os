{ lib, config, ... }:
{
  options.features.base.mpd = {
    enable = lib.mkEnableOption "MPD music player";
  };

  config = lib.mkIf config.features.base.mpd.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, config, ... }:
    let
      musicDir = "${config.home.homeDirectory}/Music";
      mpd-status = import ./mpd-status.nix { inherit pkgs; };
    in
    {
      services.mpd = {
        enable = true;
        musicDirectory = musicDir;
        extraConfig = ''
          audio_output {
            type "pipewire"
            name "PipeWire Sound Server"
          }
        '';
      };

      services.mpdris2.enable = true;

      programs.ncmpcpp = {
        enable = true;
        mpdMusicDir = musicDir;
        settings = {
          # UI
          user_interface = "alternative";
          playlist_display_mode = "columns";
          browser_display_mode = "columns";
          search_engine_display_mode = "columns";
          playlist_editor_display_mode = "columns";
          autocenter_mode = "yes";
          centered_cursor = "yes";

          # Progress bar (Catppuccin style)
          progressbar_look = "━━─";
          progressbar_color = "black:b";
          progressbar_elapsed_color = "magenta:b";

          # Colors (mapped to Catppuccin via terminal)
          colors_enabled = "yes";
          main_window_color = "white";
          header_window_color = "magenta";
          statusbar_color = "white";
          volume_color = "green";

          # Current item highlight
          current_item_prefix = "$(magenta)$r";
          current_item_suffix = "$/r$(end)";
          current_item_inactive_column_prefix = "$(blue)";
          current_item_inactive_column_suffix = "$(end)";

          # Now playing
          now_playing_prefix = "$b$(blue)";
          now_playing_suffix = "$/b$(end)";

          # Selected items
          selected_item_prefix = "$(green)";
          selected_item_suffix = "$(end)";

          # Window colors
          color1 = "white";
          color2 = "blue";
          state_line_color = "black:b";
          state_flags_color = "magenta:b";
          window_border_color = "blue";
          active_window_border = "magenta";

          # Empty tag
          empty_tag_color = "red";
        };
      };

      home.packages = [
        pkgs.mpc
        mpd-status
      ];
    };
  };
}
