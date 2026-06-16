{ lib, pkgs, ... }:

{
  services.xserver.enable = true;

  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome = {
    enable = true;
    extraGSettingsOverridePackages = [ pkgs.gsettings-desktop-schemas ];
    extraGSettingsOverrides = ''
      [org.gnome.desktop.peripherals.mouse]
      speed=1.0

      [org.gnome.desktop.peripherals.touchpad]
      speed=0.3

      [org.gnome.desktop.peripherals.pointingstick]
      scroll-method='on-button-down'
    '';
  };

  programs.niri = {
    enable = true;
    useNautilus = true;
  };

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gnome
      xdg-desktop-portal-gtk
    ];
  };

  services.printing.enable = true;

  programs.firefox.enable = true;
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

  environment.etc."xdg/autostart/easyeffects.desktop".source =
    "${pkgs.makeDesktopItem {
      name = "easyeffects";
      desktopName = "Easy Effects";
      exec = "${lib.getExe pkgs.easyeffects} --gapplication-service";
      terminal = false;
      categories = [ "AudioVideo" "Audio" ];
      startupNotify = false;
    }}/share/applications/easyeffects.desktop";

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
