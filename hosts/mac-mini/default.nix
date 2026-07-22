{ inputs, pkgs, username, ... }:

{
  imports = [
    inputs.openai-secure-tunnel-nix.darwinModules.tunnel-client
    ../../modules/darwin/cloudflared.nix
    ../../modules/darwin/local-services.nix
    ../../modules/darwin/twitter-api-safe-relay.nix
    ../../modules/darwin/twitter-api-safe-relay-mcp.nix
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";

  networking.hostName = "mac-mini";

  system.primaryUser = username;

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  services.openai-tunnel-client.instances.csbie = {
    enable = true;
    apiKeyFile = "/Users/${username}/.config/openai-tunnel/runtime-api-key";
    user = username;
    group = "staff";
    settings = {
      config_version = 1;
      control_plane.tunnel_id = "tunnel_6a602446f6708191a15202bcf5547d3d";
      health.listen_addr = "127.0.0.1:18788";
      admin_ui.open_browser = false;
      mcp.server_urls = [{
        channel = "main";
        url = "http://127.0.0.1:18787/api/mcp";
      }];
    };
    serviceConfig = {
      StandardOutPath = "/Users/${username}/Library/Logs/tunnel-client-csbie.log";
      StandardErrorPath = "/Users/${username}/Library/Logs/tunnel-client-csbie.error.log";
    };
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
