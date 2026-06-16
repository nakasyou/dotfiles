{ username, ... }:

{
  nixpkgs.hostPlatform = "aarch64-darwin";

  networking.hostName = "mac-mini";

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    extra-substituters = [
      "https://nakasyou.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nakasyou.cachix.org-1:hqgFXvJm9R1/CjzmM8Tms+6eJTMu7Oqg3bLgbSU6ojk="
    ];
  };

  # Used for backwards compatibility; read `darwin-rebuild changelog` before changing.
  system.stateVersion = 6;
}
