{ lib, config, ... }:
{
  config = lib.mkIf config.features.base.system.enable {
    networking.hostName = lib.mkDefault config.features.base.system.hostname;
    networking.networkmanager.enable = true;

    # DNS: systemd-resolved as the resolver + cache.
    services.resolved.enable = true;

    # Use glibc's nscd instead of nsncd. nsncd has an open bug
    # (twosigma/nsncd#157) where getaddrinfo returns "Name or service not
    # known" for names that have an A record but no AAAA (e.g. jiva.studio).
    services.nscd.enableNsncd = false;
  };
}
