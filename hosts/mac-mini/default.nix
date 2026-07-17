{ username, ... }:

{
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
