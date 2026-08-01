{ pkgs, username, ... }:

{
  programs.niri.enable = true;

  home-manager.users.${username}.imports = [
    ../../users/nakasyou/niri.nix
  ];

  environment.systemPackages = with pkgs; [
    brightnessctl
    mako
  ];

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-gnome
    ];
  };
}
