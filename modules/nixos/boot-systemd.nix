{ pkgs, ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # ROCm on Ryzen requires a newer kernel than the 25.11 default 6.12 series.
  boot.kernelPackages = pkgs.linuxPackages_latest;
}
