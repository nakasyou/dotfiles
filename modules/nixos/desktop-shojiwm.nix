{ inputs, pkgs, username, ... }:

{
  imports = [ inputs.shojiwm.nixosModules.default ];

  home-manager.users.${username}.imports = [
    ../../users/nakasyou/wayland-tools.nix
  ];

  programs.shojiwm = {
    enable = true;
    initConfig = {
      enable = true;
      users = [ username ];
    };
  };

  services.blueman.enable = true;

  environment.systemPackages = with pkgs; [
    pavucontrol
  ];

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-gnome
    ];
  };
}
