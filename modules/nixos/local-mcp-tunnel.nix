{
  inputs,
  pkgs,
  username,
  ...
}:

let
  homeDir = "/home/${username}";
  package = inputs.local-mcp.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  imports = [ inputs.openai-secure-tunnel-nix.nixosModules.tunnel-client ];

  environment.systemPackages = [ package ];

  services.openai-tunnel-client.instances.local-mcp = {
    enable = true;
    user = username;
    group = "users";
    environment = {
      HOME = homeDir;
      XDG_STATE_HOME = "${homeDir}/.local/state";
    };
    settings = {
      config_version = 1;
      control_plane = {
        api_key = "file:${homeDir}/.config/openai-tunnel/csbie-api-key";
        tunnel_id = "tunnel_6a6061d150988191b0618835f4441c68";
      };
      health.listen_addr = "127.0.0.1:18790";
      admin_ui.open_browser = false;
      mcp = {
        connection_max_ttl = "8760h";
        commands = [
          {
            channel = "main";
            command = "${package}/bin/local-mcp mcp";
          }
        ];
      };
    };
    serviceConfig = {
      ProtectHome = false;
      ProtectSystem = false;
      Restart = "always";
    };
  };

  # Tighten an existing manually provisioned key without creating or copying it.
  systemd.tmpfiles.rules = [
    "z ${homeDir}/.config/openai-tunnel/csbie-api-key 0600 ${username} users - -"
  ];
}
