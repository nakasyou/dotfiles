{
  imports = [
    ./hardware-configuration.nix

    ../../modules/nixos/base.nix
    ../../modules/nixos/boot-systemd.nix
    ../../modules/nixos/networking.nix
    ../../modules/nixos/opennds.nix
    ../../modules/nixos/desktop-gnome.nix
    ../../modules/nixos/desktop-niri.nix
    ../../modules/nixos/chrome-remote-desktop.nix
    ../../modules/nixos/input-ja-hazkey.nix
    ../../modules/nixos/audio.nix
    ../../modules/nixos/docker.nix
    ../../modules/nixos/nix-ld.nix
    ../../modules/nixos/tailscale.nix
    ../../modules/nixos/local-mcp-tunnel.nix
    ../../modules/nixos/hardware/amd-rocm.nix
    ../../modules/nixos/hardware/thinkpad-p14s.nix
    ../../modules/nixos/steam.nix
  ];

  security.pam.loginLimits = [
    { domain = "nakasyou"; type = "soft"; item = "memlock"; value = "614400"; }
    { domain = "nakasyou"; type = "hard"; item = "memlock"; value = "614400"; }
  ];

  networking.hostName = "p14s";
  environment.shellAliases.nix-switch = "sudo nixos-rebuild switch --flake ~/dotfiles#p14s";
  networking.nftables.enable = true;
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 3773 ];
  hardware.flipperzero.enable = true;
  virtualisation.waydroid.enable = true;
}
