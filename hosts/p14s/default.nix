{
  imports = [
    ./hardware-configuration.nix

    ../../modules/nixos/base.nix
    ../../modules/nixos/boot-systemd.nix
    ../../modules/nixos/networking.nix
    ../../modules/nixos/desktop-gnome.nix
    ../../modules/nixos/input-ja-hazkey.nix
    ../../modules/nixos/audio.nix
    ../../modules/nixos/docker.nix
    ../../modules/nixos/nix-ld.nix
    ../../modules/nixos/tailscale.nix
    ../../modules/nixos/hardware/amd-rocm.nix
    ../../modules/nixos/hardware/thinkpad-p14s.nix
  ];

  networking.hostName = "p14s";
}
