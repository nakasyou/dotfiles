{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.rustdesk-flutter ];
  systemd.services.rustdesk = {
    description = "RustDesk remote access";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "systemd-user-sessions.service" ];
    wants = [ "network.target" ];
    path = with pkgs; [ coreutils procps shadow util-linux ];
    environment = {
      PULSE_LATENCY_MSEC = "60";
      PIPEWIRE_LATENCY = "1024/48000";
    };
    serviceConfig = {
      ExecStart = "${pkgs.rustdesk-flutter}/bin/rustdesk --service";
      KillMode = "mixed";
      TimeoutStopSec = 30;
      LimitNOFILE = 100000;
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
