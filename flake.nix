{
  description = "NixOS and Home Manager configuration for nakasyou";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    moonbit-overlay.url = "github:moonbit-community/moonbit-overlay";
    nix-vite-plus.url = "github:ryoppippi/nix-vite-plus";
    llm-agents.url = "github:numtide/llm-agents.nix";
  };

  outputs = inputs@{ nixpkgs, home-manager, moonbit-overlay, nix-vite-plus, llm-agents, ... }:
    let
      username = "nakasyou";
      linuxSystem = "x86_64-linux";
      darwinSystem = "aarch64-darwin";

      mkNixosHost = { hostname, system ? linuxSystem, modules }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit hostname username;
          };
          modules = modules ++ [
            home-manager.nixosModules.home-manager
            {
              nixpkgs.overlays = [
                moonbit-overlay.overlays.default
                nix-vite-plus.overlays.default
                llm-agents.overlays.shared-nixpkgs
              ];
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.${username} = import ./users/nakasyou/home.nix;
            }
          ];
        };

      mkDarwinHost = { hostname, system ? darwinSystem, modules }:
        inputs.nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = {
            inherit hostname username;
          };
          modules = modules;
        };
    in {
      nixosConfigurations.p14s = mkNixosHost {
        hostname = "p14s";
        modules = [ ./hosts/p14s ];
      };

      darwinConfigurations.mac-mini = mkDarwinHost {
        hostname = "mac-mini";
        modules = [ ./hosts/mac-mini ];
      };
    };
}
