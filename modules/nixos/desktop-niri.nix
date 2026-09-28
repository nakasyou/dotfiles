{ inputs, pkgs, username, ... }:

let
  continuousAxisStopPatch = pkgs.writeText "niri-continuous-axis-stop.patch" ''
    diff --git a/src/input/mod.rs b/src/input/mod.rs
    --- a/src/input/mod.rs
    +++ b/src/input/mod.rs
    @@ -3494,1 +3494,1 @@
    -        if source == AxisSource::Finger {
    +        if matches!(source, AxisSource::Finger | AxisSource::Continuous) {
  '';
in

{
  environment.sessionVariables = {
    XCURSOR_THEME = "Adwaita";
    XCURSOR_SIZE = "24";
  };

  programs.niri = {
    enable = true;
    package = pkgs.niri.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ continuousAxisStopPatch ];
    });
  };

  # Niri's portal does not provide keyboard input for Computer Use.
  # The NixOS module also exports YDOTOOL_SOCKET for desktop clients.
  programs.ydotool.enable = true;
  users.users.${username}.extraGroups = [ "ydotool" ];

  home-manager.users.${username} = {
    imports = [
      inputs.dms.homeModules.dank-material-shell
      ../../users/nakasyou/wayland-tools.nix
    ];

    programs.dank-material-shell = {
      enable = true;
      systemd.enable = true;
    };

    xdg.configFile."niri/config.kdl" = {
      force = true;
      text = ''
        input {
        keyboard {
          xkb {
            layout "jp"
          }
        }

        touchpad {
          tap
          natural-scroll
        }

        trackpoint {
          accel-speed 0.2
        }
      }

      prefer-no-csd

      // Work around PipeWire format negotiation failures in screen recorders.
      debug {
        force-pipewire-invalid-modifier
      }

      output "eDP-1" {
        scale 1
      }

      layout {
        gaps 8
        center-focused-column "never"

        default-column-width { proportion 0.5; }

        focus-ring {
          width 2
          active-color "#7aa2f7"
          inactive-color "#414868"
        }

        border { off; }
      }

      binds {
        Mod+Space { spawn "dms" "ipc" "call" "spotlight" "toggle"; }
        Mod+N { spawn "dms" "ipc" "call" "notifications" "toggle"; }
        Mod+Comma { spawn "dms" "ipc" "call" "settings" "toggle"; }
        Mod+P { spawn "dms" "ipc" "call" "notepad" "toggle"; }
        Mod+V { spawn "dms" "ipc" "call" "clipboard" "toggle"; }
        Mod+X { spawn "dms" "ipc" "call" "powermenu" "toggle"; }
        Mod+Alt+N allow-when-locked=true { spawn "dms" "ipc" "call" "night" "toggle"; }
        Super+Alt+L { spawn "dms" "ipc" "call" "lock" "lock"; }

        Mod+T { spawn "ghostty"; }
        Mod+E { spawn "dolphin"; }
        Mod+Q { close-window; }
        Alt+F4 { close-window; }
        Mod+M { spawn "dms" "ipc" "call" "processlist" "toggle"; }

        Mod+F { maximize-column; }
        Mod+Shift+F { fullscreen-window; }
        Mod+Shift+M { maximize-window-to-edges; }
        Mod+Ctrl+F { expand-column-to-available-width; }
        Mod+C { center-column; }

        Mod+R { switch-preset-column-width; }
        Mod+Shift+R { switch-preset-column-width-back; }
        Mod+Ctrl+R { reset-window-height; }
        // Arrow keys keep resizing accessible on the Japanese keyboard layout.
        Mod+Alt+Left  { set-column-width "-10%"; }
        Mod+Alt+Right { set-column-width "+10%"; }
        Mod+Alt+Up    { set-window-height "-10%"; }
        Mod+Alt+Down  { set-window-height "+10%"; }

        Mod+Shift+V { toggle-window-floating; }
        Mod+Ctrl+V { switch-focus-between-floating-and-tiling; }
        Mod+W { toggle-column-tabbed-display; }
        Mod+Tab { toggle-overview; }
        Mod+F1 { show-hotkey-overlay; }

        Alt+Tab { focus-window-or-workspace-down; }
        Alt+Shift+Tab { focus-window-or-workspace-up; }

        Mod+Left  { focus-column-left; }
        Mod+Right { focus-column-right; }
        Mod+Up    { focus-window-up; }
        Mod+Down  { focus-window-down; }

        Mod+Shift+Left  { move-column-left; }
        Mod+Shift+Right { move-column-right; }
        Mod+Shift+Up    { move-column-to-workspace-up; }
        Mod+Shift+Down  { move-column-to-workspace-down; }

        Mod+Ctrl+Up   { focus-workspace-up; }
        Mod+Ctrl+Down { focus-workspace-down; }

        Mod+Ctrl+Shift+Up   { move-window-up; }
        Mod+Ctrl+Shift+Down { move-window-down; }
        Mod+Ctrl+Left  { consume-or-expel-window-left; }
        Mod+Ctrl+Right { consume-or-expel-window-right; }

        Mod+Shift+S { screenshot; }

        XF86AudioRaiseVolume allow-when-locked=true { spawn "dms" "ipc" "call" "audio" "increment" "3"; }
        XF86AudioLowerVolume allow-when-locked=true { spawn "dms" "ipc" "call" "audio" "decrement" "3"; }
        XF86AudioMute allow-when-locked=true { spawn "dms" "ipc" "call" "audio" "mute"; }
        XF86AudioMicMute allow-when-locked=true { spawn "dms" "ipc" "call" "audio" "micmute"; }
        XF86MonBrightnessUp allow-when-locked=true { spawn "dms" "ipc" "call" "brightness" "increment" "5" ""; }
        XF86MonBrightnessDown allow-when-locked=true { spawn "dms" "ipc" "call" "brightness" "decrement" "5" ""; }
        XF86AudioPlay allow-when-locked=true { spawn "playerctl" "play-pause"; }
        XF86AudioNext allow-when-locked=true { spawn "playerctl" "next"; }
        XF86AudioPrev allow-when-locked=true { spawn "playerctl" "previous"; }
        }
      '';
    };
  };

  # Keep the login keyring available in the standalone Wayland session.
  services.gnome.gnome-keyring.enable = true;

  services.blueman.enable = true;
  services.power-profiles-daemon.enable = true;

  environment.systemPackages = with pkgs; [
    brightnessctl
    pavucontrol
    playerctl
    wlsunset
    xwayland-satellite
  ];

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gnome
      xdg-desktop-portal-gtk
    ];
  };
}
