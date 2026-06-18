{ lib, pkgs, ... }:

let
  integratedCameraPowerControlPaths = [
    "/sys/bus/pci/devices/0000:c4:00.4/power/control"
    "/sys/bus/usb/devices/1-1/power/control"
  ];
  forceIntegratedCameraPowerOn =
    lib.concatMapStringsSep "\n"
      (path: ''
        if [ -w "${path}" ]; then
          echo on > "${path}"
        fi
      '')
      integratedCameraPowerControlPaths;
in
{
  services.fprintd.enable = true;

  hardware.trackpoint = {
    enable = true;
    device = "TPPS/2 Elan TrackPoint";
    sensitivity = 255;
  };

  services.xserver.inputClassSections = [
    ''
      Identifier "ELECOM Slint mouse speed"
      MatchDriver "libinput"
      MatchProduct "ELECOM Slint CH1 Mouse"
      Option "AccelSpeed" "1"
      Option "ScrollPixelDistance" "1"
    ''
  ];

  environment.etc."libinput/local-overrides.quirks".text = ''
    [Lenovo ThinkPad P14s Gen 6 AMD Trackpoint]
    MatchUdevType=pointingstick
    MatchName=*TPPS/2 Elan TrackPoint*
    MatchDMIModalias=dmi:*svnLENOVO:*:pvrThinkPadP14sGen6AMD*
    AttrTrackpointMultiplier=1.0
  '';

  services.udev = {
    extraHwdb = ''
      mouse:*:name:ELECOM Slint CH1 Mouse:
        MOUSE_WHEEL_CLICK_ANGLE=60
    '';
    extraRules = ''
      # Keep the integrated camera's USB controller out of runtime PM; it drops off the bus after s2idle resume.
      ACTION=="add", SUBSYSTEM=="pci", KERNEL=="0000:c4:00.4", ATTR{power/control}="on"
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="174f", ATTR{idProduct}=="11b4", TEST=="power/control", ATTR{power/control}="on"
    '';
  };

  systemd.services.trackpoint-sensitivity-override = {
    description = "Force TrackPoint sensitivity after device init";
    wantedBy = [ "sysinit.target" ];
    after = [ "trackpoint.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      if [ -w /sys/devices/platform/i8042/serio1/sensitivity ]; then
        echo 255 > /sys/devices/platform/i8042/serio1/sensitivity
      fi
    '';
  };

  systemd.services.integrated-camera-power-workaround = {
    description = "Disable runtime PM for the integrated camera USB path";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udevd.service" ];
    serviceConfig.Type = "oneshot";
    script = forceIntegratedCameraPowerOn;
  };

  environment.etc."systemd/system-sleep/integrated-camera-power-workaround" = {
    mode = "0755";
    text = ''
      #!${pkgs.runtimeShell}
      case "$1" in
        post)
          ${forceIntegratedCameraPowerOn}
          ;;
      esac
    '';
  };

  nixpkgs.overlays = [
    (final: prev: {
      libinput = prev.libinput.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace src/evdev.c \
            --replace-fail 'DEFAULT_BUTTON_SCROLL_TIMEOUT usec_from_millis(200)' \
                            'DEFAULT_BUTTON_SCROLL_TIMEOUT usec_from_millis(50)'
        '';
      });
    })
  ];
}
