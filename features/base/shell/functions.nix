{ lib, config, ... }:

let
  # features.base.shell.projectsRoot, spliced into fish rather than hardcoded.
  projectsRoot = config.features.base.shell.projectsRoot;
  # The component scan below walks the path segment by segment, so it needs the
  # last segment of the root ("code" for a root of "work/code").
  projectsLeaf = lib.last (lib.splitString "/" projectsRoot);
in
{
  config = lib.mkIf config.features.base.shell.enable {
    home-manager.users.${config.features.base.system.user.name} = {
      programs.fish.functions = {
        mkcd = "mkdir -p $argv[1] && cd $argv[1]";
        title = ''
          if test (count $argv) -eq 0
            set -l path (pwd)
            if string match -q "*/${projectsRoot}/*/*" $path
              set -l parts (string split "/" $path)
              for i in (seq (count $parts))
                if test "$parts[$i]" = "${projectsLeaf}"
                  set company $parts[(math $i + 1)]
                  set project $parts[(math $i + 2)]
                  break
                end
              end
              printf '\033]0;%s :: %s\007' $company $project
            end
          else
            printf '\033]0;%s\007' "$argv"
          end
        '';
        set-tab-title = ''
          set -l title
          if test (count $argv) -eq 0
            read -p 'echo "Tab title: "' title
          else
            set title "$argv"
          end
          printf '\033]1337;SetUserVar=%s=%s\007' tab_title (printf '%s' "$title" | base64)
        '';
        extract = ''
          if test -f $argv[1]
            switch $argv[1]
              case "*.tar.bz2"; tar xjf $argv[1]
              case "*.tar.gz"; tar xzf $argv[1]
              case "*.tar.xz"; tar xf $argv[1]
              case "*.bz2"; bunzip2 $argv[1]
              case "*.gz"; gunzip $argv[1]
              case "*.tar"; tar xf $argv[1]
              case "*.zip"; unzip $argv[1]
              case "*.7z"; 7z x $argv[1]
              case "*"; echo "Unknown archive format: $argv[1]"
            end
          else
            echo "File not found: $argv[1]"
          end
        '';
      };
    };
  };
}
