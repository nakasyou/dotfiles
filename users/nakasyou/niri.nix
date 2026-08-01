{ pkgs, ... }:

{
  xdg.configFile = {
    "niri/config.kdl".text = ''
      input {
        keyboard {
          xkb {
            layout "us"
          }
          repeat-delay 250
          repeat-rate 35
        }

        touchpad {
          tap
          natural-scroll
          dwt
        }

        focus-follows-mouse max-scroll-amount="0%"
      }

      output "eDP-1" {
        scale 1.0
      }

      layout {
        gaps 12
        center-focused-column "never"

        preset-column-widths {
          proportion 0.33333
          proportion 0.5
          proportion 0.66667
        }

        default-column-width { proportion 0.5; }

        focus-ring {
          width 2
          active-color "#7aa2f7"
          inactive-color "#3b4261"
        }

        border { off; }
      }

      spawn-at-startup "waybar"
      spawn-at-startup "mako"
      spawn-at-startup "nm-applet" "--indicator"

      prefer-no-csd
      screenshot-path "~/Pictures/Screenshots/%Y-%m-%d_%H-%M-%S.png"
      hotkey-overlay { skip-at-startup; }

      binds {
        Mod+Return { spawn "ghostty"; }
        Mod+D { spawn "fuzzel"; }
        Mod+Shift+E { quit; }
        Mod+Shift+Slash { show-hotkey-overlay; }

        Mod+Q { close-window; }
        Mod+H { focus-column-left; }
        Mod+J { focus-window-down; }
        Mod+K { focus-window-up; }
        Mod+L { focus-column-right; }
        Mod+Shift+H { move-column-left; }
        Mod+Shift+J { move-window-down; }
        Mod+Shift+K { move-window-up; }
        Mod+Shift+L { move-column-right; }

        Mod+1 { focus-workspace 1; }
        Mod+2 { focus-workspace 2; }
        Mod+3 { focus-workspace 3; }
        Mod+4 { focus-workspace 4; }
        Mod+5 { focus-workspace 5; }
        Mod+Shift+1 { move-column-to-workspace 1; }
        Mod+Shift+2 { move-column-to-workspace 2; }
        Mod+Shift+3 { move-column-to-workspace 3; }
        Mod+Shift+4 { move-column-to-workspace 4; }
        Mod+Shift+5 { move-column-to-workspace 5; }

        Mod+F { maximize-column; }
        Mod+Shift+F { fullscreen-window; }
        Mod+C { center-column; }
        Mod+R { switch-preset-column-width; }

        Print { screenshot; }
        Ctrl+Print { screenshot-screen; }
        Alt+Print { screenshot-window; }

        XF86AudioRaiseVolume allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+"; }
        XF86AudioLowerVolume allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-"; }
        XF86AudioMute allow-when-locked=true { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }
        XF86AudioMicMute allow-when-locked=true { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle"; }
        XF86MonBrightnessUp allow-when-locked=true { spawn "brightnessctl" "set" "+10%"; }
        XF86MonBrightnessDown allow-when-locked=true { spawn "brightnessctl" "set" "10%-"; }
      }
    '';

    "fuzzel/fuzzel.ini".text = ''
      [main]
      font=Noto Sans CJK JP:size=13
      terminal=ghostty
      width=42
      lines=12
      horizontal-pad=20
      vertical-pad=14
      inner-pad=8
      prompt="❯  "

      [colors]
      background=1a1b26f2
      text=c0caf5ff
      prompt=7aa2f7ff
      placeholder=565f89ff
      input=c0caf5ff
      match=bb9af7ff
      selection=33467cff
      selection-text=c0caf5ff
      border=7aa2f7ff

      [border]
      width=2
      radius=10
    '';

    "mako/config".text = ''
      font=Noto Sans CJK JP 11
      background-color=#1a1b26ee
      text-color=#c0caf5
      border-color=#7aa2f7
      border-size=2
      border-radius=10
      width=360
      height=120
      margin=12
      padding=14
      default-timeout=6000
      icons=1
      max-icon-size=48

      [urgency=high]
      border-color=#f7768e
      default-timeout=0
    '';

    "waybar/config".text = builtins.toJSON {
      layer = "top";
      position = "top";
      height = 34;
      spacing = 6;
      modules-left = [ "niri/workspaces" "niri/window" ];
      modules-center = [ "clock" ];
      modules-right = [ "tray" "network" "pulseaudio" "battery" ];
      "niri/workspaces" = {
        format = "{value}";
        on-click = "activate";
      };
      "niri/window" = {
        format = "{title}";
        max-length = 60;
      };
      clock = {
        format = "{:%m/%d %H:%M}";
        format-alt = "{:%Y-%m-%d (%a) %H:%M:%S}";
        tooltip-format = "<big>{:%Y年 %B}</big>\n<tt><small>{calendar}</small></tt>";
      };
      network = {
        format-wifi = "󰤨  {signalStrength}%";
        format-ethernet = "󰈀";
        format-disconnected = "󰤭";
        tooltip-format = "{ifname}: {ipaddr}/{cidr}";
        on-click = "nm-connection-editor";
      };
      pulseaudio = {
        format = "{icon}  {volume}%";
        format-muted = "󰝟  muted";
        format-icons.default = [ "" "" "" ];
        on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        on-click-right = "pavucontrol";
      };
      battery = {
        states = {
          warning = 30;
          critical = 15;
        };
        format = "{icon}  {capacity}%";
        format-charging = "󰂄  {capacity}%";
        format-icons = [ "󰁺" "󰁻" "󰁽" "󰁿" "󰂁" "󰁹" ];
      };
      tray.spacing = 8;
    };

    "waybar/style.css".text = ''
      * {
        border: none;
        border-radius: 0;
        font-family: "Symbols Nerd Font", "Noto Sans CJK JP", sans-serif;
        font-size: 13px;
        min-height: 0;
      }

      window#waybar {
        background: rgba(26, 27, 38, 0.94);
        color: #c0caf5;
      }

      #workspaces button {
        padding: 0 9px;
        color: #565f89;
      }

      #workspaces button.active {
        background: #33467c;
        color: #c0caf5;
      }

      #window { color: #a9b1d6; }

      #clock,
      #network,
      #pulseaudio,
      #battery,
      #tray {
        padding: 0 10px;
        margin: 5px 2px;
        border-radius: 8px;
        background: #24283b;
      }

      #clock { color: #7aa2f7; }
      #network { color: #9ece6a; }
      #pulseaudio { color: #bb9af7; }
      #battery { color: #e0af68; }
      #battery.critical:not(.charging) { color: #f7768e; }
    '';
  };

  home.packages = with pkgs; [
    mako
    nerd-fonts.symbols-only
  ];
}
