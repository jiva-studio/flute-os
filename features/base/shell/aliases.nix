{ lib, config, ... }:
{
  config = lib.mkIf config.features.base.shell.enable {
    home-manager.users.${config.features.base.system.user.name} = {
      programs.fish.shellAliases = {
        ls = "eza"; ll = "eza -l"; la = "eza -la"; lt = "eza --tree";
        cat = "bat"; grep = "rg"; find = "fd";
        g = "git"; gs = "git status"; ga = "git add"; gc = "git commit";
        gp = "git push"; gl = "git log --oneline"; gd = "git diff";
        nrs = "sudo nixos-rebuild switch --flake .";
        nrt = "sudo nixos-rebuild test --flake .";
        nrb = "sudo nixos-rebuild boot --flake .";
        nfu = "nix flake update";
        # Tailscale fast-switch between tailnets: `net <tailnet>`, `nets` to list
        # the ones this machine is logged in to.
        net = "tailscale switch"; nets = "tailscale switch --list";
        ".." = "cd .."; "..." = "cd ../.."; cls = "clear";
      };
    };
  };
}
