{ inputs, pkgs, username, ... }:

let
  tunnelClientConfig = (pkgs.formats.yaml { }).generate "tunnel-client-csbie.yaml" {
    config_version = 1;
    control_plane = {
      tunnel_id = "tunnel_6a5f7d1997748191a10ca77552ddb0ce";
      api_key = "env:CONTROL_PLANE_API_KEY";
    };
    health.listen_addr = "127.0.0.1:18788";
    admin_ui.open_browser = false;
    mcp.server_urls = [{
      channel = "csbie";
      url = "http://127.0.0.1:18787/api/mcp";
    }];
  };
  tunnelClient =
    inputs.openai-secure-tunnel-nix.packages.${pkgs.stdenv.hostPlatform.system}.tunnel-client;
in {
  imports = [
    ../../modules/darwin/cloudflared.nix
    ../../modules/darwin/local-services.nix
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";

  networking.hostName = "mac-mini";

  system.primaryUser = username;

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  launchd.daemons.tunnel-client-csbie.serviceConfig = {
    ProgramArguments = [
      "${tunnelClient}/bin/tunnel-client"
      "run"
      "--config"
      "${tunnelClientConfig}"
    ];
    RunAtLoad = true;
    KeepAlive = {
      SuccessfulExit = false;
    };
    ProcessType = "Background";
    ThrottleInterval = 2;
    UserName = username;
    GroupName = "staff";
    EnvironmentVariables.CONTROL_PLANE_API_KEY =
      "file:/Users/${username}/.config/openai-tunnel/runtime-api-key";
    StandardOutPath = "/var/log/tunnel-client-csbie.log";
    StandardErrorPath = "/var/log/tunnel-client-csbie.error.log";
  };

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    extra-substituters = [
      "https://cache.nakasyou.how"
    ];
    extra-trusted-public-keys = [
      "cache.nakasyou.how-1:BumjaqVgJE6uAuaJcoV1oeFKPEyPxZ73XNmxVskqQZM="
    ];
  };

  # Used for backwards compatibility; read `darwin-rebuild changelog` before changing.
  system.stateVersion = 6;
}
