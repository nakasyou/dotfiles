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
    ../../modules/nixos/rustdesk.nix
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

  networking.hostName = "p14s";
  networking.nftables.enable = true;
  hardware.flipperzero.enable = true;
  virtualisation.waydroid.enable = true;
}
