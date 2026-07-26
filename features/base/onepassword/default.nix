{ lib, config, ... }:
{
  options.features.base.onepassword = {
    enable = lib.mkEnableOption "1Password password manager";
  };

  config = lib.mkIf config.features.base.onepassword.enable {
    # CLI: provides the `op` command for reading/creating secrets from the
    # terminal (system-level setuid wrapper).
    programs._1password.enable = true;

    # GUI app + system integration (polkit). Enabling it here (instead of a
    # plain home package) sets up the kernel group and lets the desktop app
    # unlock the CLI via biometrics/system auth — the "Integrate with
    # 1Password CLI" toggle in the app.
    programs._1password-gui = {
      enable = true;
      polkitPolicyOwners = [ config.features.base.system.user.name ];
    };
  };
}
