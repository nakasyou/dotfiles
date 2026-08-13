{ pkgs, ... }:

{
  xdg.configFile = {
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

    "wofi/config".text = ''
      show=drun
      width=720
      height=480
      columns=4
      lines=3
      allow_images=true
      image_size=48
      insensitive=true
      prompt=アプリを検索
      hide_scroll=true
      no_actions=true
    '';

    "wofi/style.css".text = ''
      * {
        font-family: "Noto Sans CJK JP", sans-serif;
        font-size: 13px;
      }

      window {
        margin: 0;
        padding: 18px;
        border: 2px solid #7aa2f7;
        border-radius: 16px;
        background-color: rgba(26, 27, 38, 0.97);
      }

      #input {
        margin: 4px 4px 16px;
        padding: 12px 16px;
        border: 1px solid #414868;
        border-radius: 10px;
        color: #c0caf5;
        background-color: #24283b;
      }

      #inner-box {
        margin: 0;
      }

      #entry {
        min-width: 140px;
        min-height: 104px;
        margin: 6px;
        padding: 14px 10px;
        border-radius: 12px;
        color: #c0caf5;
        background-color: #24283b;
      }

      #entry:selected {
        color: #ffffff;
        background-color: #33467c;
        outline: 2px solid #7aa2f7;
      }

      #img {
        margin: 0 10px 0 0;
      }

      #text {
        color: inherit;
      }
    '';

    "waybar/config".text = builtins.toJSON {
      layer = "top";
      position = "top";
      height = 34;
      spacing = 6;
      modules-left = [ "wlr/taskbar" ];
      modules-center = [ "clock" ];
      modules-right = [ "tray" "network" "pulseaudio" "battery" ];
      "wlr/taskbar" = {
        format = "{icon}";
        icon-size = 18;
        on-click = "activate";
        on-click-middle = "close";
        tooltip-format = "{title}";
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
    nerd-fonts.symbols-only
  ];
}
