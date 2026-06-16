{ username, ... }:

{
  nixpkgs.hostPlatform = "aarch64-darwin";

  networking.hostName = "mac-mini";

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Used for backwards compatibility; read `darwin-rebuild changelog` before changing.
  system.stateVersion = 6;
}
