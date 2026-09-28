{ config, lib, pkgs, ... }:

let
  cfg = config.services.opennds;
  opennds = pkgs.callPackage ../../pkgs/opennds.nix { };

  configFile = pkgs.writeText "opennds.conf" ''
    config opennds 'setup'
      option enabled '1'
      option gatewayinterface '${cfg.gatewayInterface}'
      option gatewayname '${cfg.gatewayName}'
      option gatewayport '${toString cfg.gatewayPort}'
      option gatewayfqdn '${cfg.gatewayFQDN}'
      option webroot '${cfg.package}/share/opennds/htdocs'
      option statuspath '${cfg.package}/libexec/opennds/client_params.sh'
      option binauth '${cfg.package}/libexec/opennds/binauth_log.sh'
      option custombinauth '${cfg.package}/libexec/opennds/custombinauth.sh'
      list users_to_router 'allow udp port 53'
      list users_to_router 'allow tcp port 53'
      list users_to_router 'allow udp port 67'
      list users_to_router 'allow tcp port 80'
      list users_to_router 'allow tcp port ${toString cfg.gatewayPort}'
      list authenticated_users 'allow all'

    ${cfg.extraConfig}
  '';
in
{
  options.services.opennds = {
    enable = lib.mkEnableOption "openNDS captive portal";

    package = lib.mkOption {
      type = lib.types.package;
      default = opennds;
      description = "The openNDS package to use.";
    };

    gatewayInterface = lib.mkOption {
      type = lib.types.str;
      default = "br-lan";
      example = "br-hotspot";
      description = ''
        Interface managed by openNDS. It must have an IPv4 address and should
        be a bridge rather than a physical wireless interface.
      '';
    };

    gatewayName = lib.mkOption {
      type = lib.types.str;
      default = "openNDS";
      description = "Name shown by the default captive portal.";
    };

    gatewayPort = lib.mkOption {
      type = lib.types.port;
      default = 2050;
      description = "Port used by openNDS's embedded HTTP server.";
    };

    gatewayFQDN = lib.mkOption {
      type = lib.types.str;
      default = "status.client";
      description = "Synthetic hostname used for the client status page.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional UCI-style openNDS configuration lines.";
    };
  };

  config = {
    environment.systemPackages = [ cfg.package ];

    environment.etc."config/opennds" = lib.mkIf cfg.enable {
      source = configFile;
    };

    boot.kernel.sysctl = lib.mkIf cfg.enable {
      "net.ipv4.ip_forward" = 1;
    };

    networking.firewall.interfaces.${cfg.gatewayInterface} = lib.mkIf cfg.enable {
      allowedTCPPorts = [ 80 cfg.gatewayPort ];
      allowedUDPPorts = [ 53 67 ];
    };

    systemd.services.opennds = lib.mkIf cfg.enable {
      description = "openNDS Captive Portal";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "NetworkManager.service" "network-online.target" ];
      restartTriggers = [ configFile ];
      path = with pkgs; [
        bash
        coreutils
        curl
        dnsmasq
        gawk
        gnugrep
        gnused
        iproute2
        ipset
        iptables
        iw
        nftables
        procps
        util-linux
        wget
      ];
      serviceConfig = {
        Type = "forking";
        ExecStart = "${cfg.package}/bin/opennds -b";
        Restart = "on-failure";
        RestartSec = 20;
      };
    };
  };
}
