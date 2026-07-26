# Extra trusted CA certificates.
#
# General-purpose: give it a list of PEM root/intermediate certs and they are
# trusted both system-wide (security.pki → curl, git, etc.) and in Firefox
# (explicit Certificates.Install policy — NOT ImportEnterpriseRoots, so only
# these certs are added, nothing else from the OS store leaks in).
#
# This module carries no app/host specifics — what to trust is data, supplied
# by the host/personal layer, e.g.:
#   features.base.certificates.trusted = [ ../../some/where/root-ca.crt ];
{ lib, config, ... }:
let
  cfg = config.features.base.certificates;
  userName = config.features.base.system.user.name;
in
{
  options.features.base.certificates = {
    trusted = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      example = lib.literalExpression "[ ./root-ca.crt ]";
      description = ''
        PEM CA certificates to trust system-wide and in Firefox. Each entry is
        added to security.pki.certificateFiles and to Firefox's explicit
        Certificates.Install policy (when the Firefox feature is enabled).
      '';
    };
  };

  config = lib.mkIf (cfg.trusted != [ ]) (lib.mkMerge [
    { security.pki.certificateFiles = cfg.trusted; }

    (lib.mkIf config.features.base.firefox.enable {
      home-manager.users.${userName}.programs.firefox.policies.Certificates.Install = cfg.trusted;
    })
  ]);
}
