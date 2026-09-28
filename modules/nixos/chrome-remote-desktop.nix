{ pkgs, username, ... }:
let
  host = import ../../pkgs/chrome-remote-desktop.nix { inherit pkgs; };
in {
  environment.systemPackages = [ host ];
  services.xserver.desktopManager.xfce.enable = true;
  security.pam.services.chrome-remote-desktop = { };
  # Google's registration binary calls this absolute path.
  systemd.tmpfiles.rules = [
    "L+ /opt/google/chrome-remote-desktop - - - - ${host}/lib/chrome-remote-desktop"
  ];

  # A separate X11 desktop avoids interfering with the local Wayland session.
  environment.etc."chrome-remote-desktop-session".text = ''
    exec ${pkgs.dbus}/bin/dbus-run-session ${pkgs.xfce.xfce4-session}/bin/xfce4-session
  '';
  systemd.services."chrome-remote-desktop@" = {
    description = "Chrome Remote Desktop for %i";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.ConditionPathExistsGlob = "/home/%i/.config/chrome-remote-desktop/host#*.json";
    environment = {
      CHROME_REMOTE_DESKTOP_USE_XVFB = "1";
      XDG_SESSION_CLASS = "user";
      XDG_SESSION_TYPE = "x11";
    };
    path = with pkgs; [ host xfce.xfce4-session xfce.xfwm4 xfce.xfce4-panel xfce.xfdesktop xfce.xfconf xfce.thunar xfce.xfce4-settings ];
    serviceConfig = {
      Type = "simple";
      User = "%i";
      PAMName = "chrome-remote-desktop";
      TTYPath = "/dev/chrome-remote-desktop";
      ExecStart = "${host}/bin/chrome-remote-desktop --start --new-session";
      ExecReload = "${host}/bin/chrome-remote-desktop --reload";
      ExecStop = "${host}/bin/chrome-remote-desktop --stop";
      RestartForceExitStatus = 41;
    };
  };
  systemd.targets.multi-user.wants = [ "chrome-remote-desktop@${username}.service" ];
}
