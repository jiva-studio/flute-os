# Tailscale "networks" — ALWAYS-UP, multi-tailnet model.
#
# Plumbing only: which tailnets exist, whose accounts they are and what they
# forward are all values, stated per host through the options below. Nothing
# here names a network, an account or a machine.
#
# Earlier this was a one-at-a-time *switcher* (kernel tailscaled + `tailscale
# switch`). The CGNAT range (100.64.0.0/10) is shared by every tailnet, so only
# ONE can own the kernel `tailscale0`/MagicDNS at a time — hence switching.
#
# New model: each tailnet runs its own **userspace** `tailscaled` (no root, no
# TUN, no kernel route/DNS fight), exposing a local SOCKS5 proxy. They are all
# up simultaneously. Per-service `socat` forwarders bridge a fixed loopback port
# through the right SOCKS5, so consumers (.mcp.json, etc.) just talk to
# 127.0.0.1:<port> and never know about tailnets. socat sends the hostname to
# the proxy (SOCKS5 ATYP=domain), so MagicDNS names resolve on the tailscaled
# side — no hardcoded tailscale IPs.
#
# Port convention (block 18xxx, /100 per tailnet — see networks below):
#   18x00 = that tailnet's SOCKS5 daemon; 18x01.. = its forwarders.
#
# First-time / re-auth: each userspace daemon has its OWN state dir, so it must
# be logged in once with `fluteos-tailnet-login <name>` (state persists across
# restarts). The waybar widget is now a STATUS indicator (how many tailnets are
# connected + which); click → login picker for a disconnected one.
#
# Two registry sources feed the widget's labels/icons:
#   - host-scope tailnet: features.fluteos.tailnets.host;
#   - project-scope tailnets: features.fluteos.projects.effective.<p>.tailnet.
# The always-up daemons/forwarders themselves come from the explicit
# `networks` option, stated per host.
{ lib, config, pkgs, ... }:
let
  theme = config.features.fluteos.theme.resolved;
in
{
  options.features.fluteos.tailnets = {
    enable = lib.mkEnableOption "Tailscale userspace networks + waybar status widget";

    host = lib.mkOption {
      default = null;
      description = "Host-scope (personal) tailnet — feeds the widget's label/icon registry.";
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          account = lib.mkOption {
            type = lib.types.str;
            description = "Tailscale account/profile id for the personal tailnet.";
          };
          domain = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Personal tailnet MagicDNS domain (e.g. <name>.ts.net).";
          };
          displayName = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Widget label; null → \"Personal\".";
          };
          icon = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Widget icon; null → 🏠.";
          };
        };
      });
    };

    networks = lib.mkOption {
      default = { };
      description = ''
        Always-up tailnets to bring up as userspace daemons on this host, keyed
        by a short slug (used for service/state/runtime dir names). Each gets its
        own `tailscaled --tun=userspace-networking` with a SOCKS5 proxy, plus a
        `socat` loopback forwarder per entry in `forwards`.
      '';
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          account = lib.mkOption {
            type = lib.types.str;
            description = "Tailscale account this userspace daemon logs into (via fluteos-tailnet-login).";
          };
          socksPort = lib.mkOption {
            type = lib.types.port;
            description = "Loopback SOCKS5 port for this tailnet's daemon (convention: 18x00).";
          };
          routes = lib.mkOption {
            default = [ ];
            type = lib.types.listOf lib.types.str;
            description = ''
              Tailnet IPs/CIDRs to make reachable system-wide (ping/curl/browser/
              any app) by routing them — in the KERNEL — into this tailnet via a
              tun2socks device backed by this net's SOCKS5 proxy. The userspace
              model has no `tailscale0`, so 100.64.0.0/10 is otherwise unroutable;
              tun2socks (gVisor) carries TCP/UDP/ICMP. List the specific peer /32s
              you need (the shared CGNAT range can't be split between tailnets, so
              do NOT route the whole 100.64.0.0/10). Do not list this host's own
              tailnet IP. Empty → no tun for this net (SOCKS-only, as before).
            '';
            # Illustrative addresses. Product documentation should not publish
            # live tailnet peers, which is what the previous example did.
            example = [ "100.64.1.2/32" "100.64.3.4/32" ];
          };
          forwards = lib.mkOption {
            default = { };
            description = "Loopback port forwarders bridged through this tailnet's SOCKS5.";
            type = lib.types.attrsOf (lib.types.submodule {
              options = {
                localPort = lib.mkOption {
                  type = lib.types.port;
                  description = "127.0.0.1 port to listen on (convention: 18x01..).";
                };
                host = lib.mkOption {
                  type = lib.types.str;
                  description = "Target host inside the tailnet (MagicDNS name; resolved by the proxy).";
                };
                remotePort = lib.mkOption {
                  type = lib.types.port;
                  description = "Target port on `host`.";
                };
              };
            });
          };
        };
      });
    };
  };

  config = lib.mkIf config.features.fluteos.tailnets.enable (
  let
    # --- System-wide kernel reachability via tun2socks ----------------------
    # SOCKS5 alone only carries the per-port loopback forwarders; the kernel
    # still has no route into 100.64.0.0/10 (userspace model = no tailscale0),
    # so ping/curl/any app to a tailnet IP fails. For each network that lists
    # `routes`, run a tun2socks device whose gVisor stack carries TCP/UDP/ICMP
    # to this net's SOCKS5, and install /32 (etc.) routes pointing at it. The
    # shared CGNAT range can't be split between tailnets, so only the explicit
    # per-peer routes are installed — both tailnets stay up simultaneously.
    nets = config.features.fluteos.tailnets.networks;
    routedNets = lib.filterAttrs (_: net: net.routes != [ ]) nets;
    ip = "${pkgs.iproute2}/bin/ip";
    # Each tun gets a distinct dummy /24 from the benchmarking range (RFC 2544,
    # 198.18.0.0/15) purely so the kernel has a source address when emitting the
    # SYN into the device; tun2socks ignores it and dials the SOCKS proxy by the
    # original destination, so the value never appears on the wire.
    mkTunService = idx: netName:
      let
        net = routedNets.${netName};
        dev = "tun-${netName}"; # keep ≤ 15 chars (IFNAMSIZ-1)
        addr = "198.18.${toString idx}.1/24";
        routesStr = lib.concatStringsSep " " net.routes;
        up = pkgs.writeShellScript "tailnet-tun-up-${netName}" ''
          set -u
          dev="${dev}"
          # tun2socks creates the device asynchronously — wait for it (≤5s).
          for _ in $(seq 1 50); do ${ip} link show "$dev" >/dev/null 2>&1 && break; sleep 0.1; done
          ${ip} addr replace ${addr} dev "$dev" 2>/dev/null || true
          ${ip} link set "$dev" up || true
          for r in ${routesStr}; do ${ip} route replace "$r" dev "$dev"; done
        '';
        down = pkgs.writeShellScript "tailnet-tun-down-${netName}" ''
          set -u
          dev="${dev}"
          for r in ${routesStr}; do ${ip} route del "$r" dev "$dev" 2>/dev/null || true; done
        '';
      in
      lib.nameValuePair "tailnet-tun-${netName}" {
        description = "Kernel reachability for tailnet ${netName} — tun2socks ${dev} → SOCKS5 :${toString net.socksPort}";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.tun2socks}/bin/tun2socks -device tun://${dev} -proxy socks5://127.0.0.1:${toString net.socksPort}";
          ExecStartPost = "${up}";
          ExecStopPost = "${down}";
          # tun2socks keeps running even while its SOCKS5 (a user service that
          # comes up at login) is down — it just fails per-connection until then.
          Restart = "always";
          RestartSec = 2;
        };
      };
    tunServices = lib.listToAttrs
      (lib.imap0 mkTunService (lib.attrNames routedNets));
  in
  {
    boot.kernelModules = lib.mkIf (routedNets != { }) [ "tun" ];
    systemd.services = tunServices;

    home-manager.users.${config.features.base.system.user.name} =
      { osConfig, config, pkgs, lib, ... }:
      let
        hostNet = osConfig.features.fluteos.tailnets.host or null;
        nets = osConfig.features.fluteos.tailnets.networks or { };

        # --- Display registry (labels/icons), deduped by account ---------------
        # `or { }` because features.fluteos.projects is optional: it declares
        # `effective` on the home-manager side only when it is enabled, and
        # tailnets has to stand on its own without it.
        projectNets = lib.filter (x: x != null) (lib.mapAttrsToList
          (_: eff:
            if eff.tailnet == null then null else {
              account = eff.tailnet.account;
              domain = eff.tailnet.domain;
              displayName =
                if eff.tailnet.displayName != null then eff.tailnet.displayName
                else eff.displayName;
              icon = if eff.tailnet.icon != null then eff.tailnet.icon else eff.icon;
            })
          (config.features.fluteos.projects.effective or { }));

        hostEntry = lib.optional (hostNet != null) {
          account = hostNet.account;
          domain = hostNet.domain;
          displayName = if hostNet.displayName != null then hostNet.displayName else "Personal";
          icon = if hostNet.icon != null then hostNet.icon else "🏠";
        };

        allNets = hostEntry ++ projectNets;
        byAccount = lib.groupBy (n: n.account) allNets;
        registryAttrs = lib.mapAttrs (_: entries: lib.head entries) byAccount;

        # --- systemd user services: one userspace daemon per tailnet -----------
        daemonServices = lib.mapAttrs'
          (netName: net: lib.nameValuePair "tailscaled-${netName}" {
            Unit = {
              Description = "Tailscale userspace daemon — ${netName} (SOCKS5 :${toString net.socksPort})";
              After = [ "network-online.target" ];
              Wants = [ "network-online.target" ];
            };
            Service = {
              Type = "simple";
              StateDirectory = "tailscaled-${netName}";
              RuntimeDirectory = "tailscaled-${netName}";
              ExecStart = lib.concatStringsSep " " [
                "${pkgs.tailscale}/bin/tailscaled"
                "--tun=userspace-networking"
                "--statedir=%S/tailscaled-${netName}"
                "--socket=%t/tailscaled-${netName}/tailscaled.sock"
                "--socks5-server=127.0.0.1:${toString net.socksPort}"
                "--port=0"
              ];
              Restart = "on-failure";
              RestartSec = 2;
            };
            Install.WantedBy = [ "default.target" ];
          })
          nets;

        # --- systemd user services: one socat forwarder per forward ------------
        # Resolve a bare hostname to its tailnet FQDN (domain from the registry)
        # so the proxy-side MagicDNS lookup is unambiguous; pass dotted names /
        # IPs through untouched.
        netDomain = net: (registryAttrs.${net.account} or { }).domain or "";
        fqdn = net: host:
          let d = netDomain net; in
          if (lib.hasInfix "." host) || d == "" then host else "${host}.${d}";

        forwardServices = lib.listToAttrs (lib.concatLists (lib.mapAttrsToList
          (netName: net: lib.mapAttrsToList
            (fwdName: fwd: lib.nameValuePair "tailnet-fwd-${netName}-${fwdName}" {
              Unit = {
                Description = "tailnet forward ${netName}/${fwdName}: 127.0.0.1:${toString fwd.localPort} → ${fqdn net fwd.host}:${toString fwd.remotePort}";
                After = [ "tailscaled-${netName}.service" ];
                PartOf = [ "tailscaled-${netName}.service" ];
              };
              Service = {
                ExecStart = lib.concatStringsSep " " [
                  "${pkgs.socat}/bin/socat"
                  "TCP-LISTEN:${toString fwd.localPort},fork,reuseaddr,bind=127.0.0.1"
                  "SOCKS5-CONNECT:127.0.0.1:${toString net.socksPort}:${fqdn net fwd.host}:${toString fwd.remotePort}"
                ];
                Restart = "always";
                RestartSec = 2;
              };
              Install.WantedBy = [ "default.target" ];
            })
            net.forwards)
          nets));

        # --- widget metadata: per-net icon/label + runtime socket --------------
        widgetNets = lib.mapAttrsToList
          (netName: net:
            let reg = registryAttrs.${net.account} or { }; in {
              name = netName;
              account = net.account;
              icon = reg.icon or "🔗";
              disp = reg.displayName or netName;
              sock = "tailscaled-${netName}/tailscaled.sock"; # relative to $XDG_RUNTIME_DIR
            })
          nets;
        widgetFile = pkgs.writeText "tailnets-widget.json" (builtins.toJSON widgetNets);

        watch = pkgs.writeShellScriptBin "fluteos-tailnet-watch" ''
          export JQ="${pkgs.jq}/bin/jq"
          export TAILSCALE="${pkgs.tailscale}/bin/tailscale"
          export NETS="${widgetFile}"
          bash ${./fluteos-tailnet-watch.sh}
        '';

        menu = pkgs.writeShellScriptBin "fluteos-tailnet-menu" ''
          export JQ="${pkgs.jq}/bin/jq"
          export TAILSCALE="${pkgs.tailscale}/bin/tailscale"
          export FUZZEL="${pkgs.fuzzel}/bin/fuzzel"
          export WEZTERM="${pkgs.wezterm}/bin/wezterm"
          export NOTIFY_SEND="${pkgs.libnotify}/bin/notify-send"
          export LOGIN="${login}/bin/fluteos-tailnet-login"
          export NETS="${widgetFile}"
          ${theme.fuzzel.env}bash ${./fluteos-tailnet-menu.sh}
        '';

        # CLI: log a userspace daemon into its tailnet (one-time / re-auth).
        login = pkgs.writeShellScriptBin "fluteos-tailnet-login" ''
          set -eu
          TS="${pkgs.tailscale}/bin/tailscale"
          JQ="${pkgs.jq}/bin/jq"
          RT="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
          name="''${1:-}"
          if [ -z "$name" ]; then
            echo "usage: fluteos-tailnet-login <name>"
            echo "networks:"; "$JQ" -r '.[] | "  \(.name)  (\(.disp), \(.account))"' "${widgetFile}"
            exit 1
          fi
          sock="$("$JQ" -r --arg n "$name" '.[] | select(.name==$n) | .sock' "${widgetFile}")"
          acct="$("$JQ" -r --arg n "$name" '.[] | select(.name==$n) | .account' "${widgetFile}")"
          [ -n "$sock" ] || { echo "unknown tailnet: $name"; exit 1; }
          echo "Logging '$name' into $acct (open the URL below in a browser)…"
          exec "$TS" --socket="$RT/$sock" up --accept-dns=false \
            --hostname=${osConfig.networking.hostName}
        '';

        # CLI: dump per-net BackendState.
        status = pkgs.writeShellScriptBin "fluteos-tailnet-status" ''
          set -u
          TS="${pkgs.tailscale}/bin/tailscale"
          JQ="${pkgs.jq}/bin/jq"
          RT="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
          "$JQ" -c '.[]' "${widgetFile}" | while read -r row; do
            n="$("$JQ" -r '.name' <<<"$row")"; d="$("$JQ" -r '.disp' <<<"$row")"
            s="$("$JQ" -r '.sock' <<<"$row")"
            st="$("$TS" --socket="$RT/$s" status --json 2>/dev/null | "$JQ" -r '.BackendState // "Down"' 2>/dev/null)"
            printf '%-14s %-14s %s\n' "$n" "$d" "''${st:-Down}"
          done
        '';
      in
      {
        home.packages = [ watch menu login status pkgs.tailscale pkgs.socat ];
        systemd.user.services = daemonServices // forwardServices;
      };
  });
}
