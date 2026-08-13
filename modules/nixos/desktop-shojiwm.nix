{ inputs, pkgs, username, ... }:

{
  imports = [ inputs.shojiwm.nixosModules.default ];

  home-manager.users.${username}.imports = [
    ../../users/nakasyou/wayland-tools.nix
  ];

  programs.shojiwm = {
    enable = true;

    package = inputs.shojiwm.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
      libinput = pkgs.libinput;
    };
  };

  # Reuse the login keyring previously managed by the GNOME session. This also
  # enables PAM unlock for console logins, which is how ShojiWM is started.
  services.gnome.gnome-keyring.enable = true;

  services.blueman.enable = true;
  services.power-profiles-daemon.enable = true;

  environment.systemPackages = with pkgs; [
    brightnessctl
    pavucontrol
    wlsunset
  ];

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-gnome
    ];
  };
}
