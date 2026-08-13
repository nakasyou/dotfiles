{ lib, pkgs, ... }:

{
  networking.networkmanager = {
    enable = true;
    plugins = [ pkgs.networkmanager-openvpn ];
    wifi = {
      # Randomize only the physical Wi-Fi MAC. ProtonVPN's tunnel interfaces are unaffected.
      macAddress = "random";
      scanRandMacAddress = true;
    };
  };

  # Allow hotspot clients to obtain an address and resolve DNS through the
  # NetworkManager-managed dnsmasq instance.
  networking.firewall.interfaces.wlp194s0 = {
    allowedUDPPorts = [ 53 67 ];
    allowedTCPPorts = [ 53 ];
  };

  # NetworkManager's hotspot dnsmasq must chown its runtime/lease files before
  # dropping privileges. Without this, clients cannot complete DHCP.
  systemd.services.NetworkManager.serviceConfig.CapabilityBoundingSet =
    lib.mkAfter [ "CAP_CHOWN" ];

  environment.systemPackages = with pkgs; [
    openvpn
    wireguard-tools
  ];
}
