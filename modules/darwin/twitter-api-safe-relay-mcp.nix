{ inputs, pkgs, username, ... }:

let
  homeDir = "/Users/${username}";
  logsDir = "${homeDir}/Library/Logs/nakasyou-services";
  apiKeyFile = "${homeDir}/.config/openai-tunnel/runtime-api-key";
  package = pkgs.callPackage ../../pkgs/twitter-api-safe-relay-mcp.nix {
    src = inputs.twitter-api-safe-relay-mcp;
  };
in
{
  environment.systemPackages = [ package ];

  services.openai-tunnel-client.instances.twitter-api-safe-relay-mcp = {
    enable = true;
    apiKeyFile = apiKeyFile;
    user = username;
    group = "staff";
    environment.TWITTER_RELAY_BASE_URL = "http://127.0.0.1:3010";
    settings = {
      config_version = 1;
      control_plane.tunnel_id = "tunnel_6a6037aa0b6c81919d91bc2f0d81c75b";
      health.listen_addr = "127.0.0.1:18789";
      admin_ui.open_browser = false;
      mcp.commands = [{
        channel = "main";
        command = "${package}/bin/twitter_api_safe_relay_mcp";
      }];
    };
    serviceConfig = {
      StandardOutPath = "${logsDir}/twitter-api-safe-relay-mcp-tunnel.log";
      StandardErrorPath = "${logsDir}/twitter-api-safe-relay-mcp-tunnel.err.log";
    };
  };
}
