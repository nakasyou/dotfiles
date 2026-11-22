{ pkgs, inputs, ... }:

{
  services.xserver.enable = true;

  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  services.gnome.gnome-browser-connector.enable = false;
  services.gnome.gnome-remote-desktop.enable = false;
  environment.gnome.excludePackages = [ pkgs.gnome-connections ];

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gnome
      xdg-desktop-portal-gtk
    ];
  };

  services.printing = {
    enable = true;
    drivers = [ pkgs.cnijfilter2 ];
  };

  programs.firefox.enable = true;
  programs.firefox.package = inputs.nixpkgs-desktop-apps.legacyPackages.${pkgs.stdenv.hostPlatform.system}.firefox;
  programs.obs-studio = {
    enable = true;
    enableVirtualCamera = true;
    plugins = with pkgs.obs-studio-plugins; [
      wlrobs
      obs-backgroundremoval
      obs-pipewire-audio-capture
      obs-gstreamer
      obs-vkcapture
    ];
  };

  fonts = {
    packages = with pkgs; [
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
    ];

    fontconfig.defaultFonts = {
      serif = [
        "Noto Serif CJK JP"
        "DejaVu Serif"
      ];
      sansSerif = [
        "Noto Sans CJK JP"
        "DejaVu Sans"
      ];
      monospace = [
        "DejaVu Sans Mono"
        "Noto Sans CJK JP"
      ];
      emoji = [ "Noto Color Emoji" ];
    };
  };
}
