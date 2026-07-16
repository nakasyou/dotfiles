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
    codex-desktop-linux.url = "github:ilysenko/codex-desktop-linux";
    nix-vite-plus.url = "github:ryoppippi/nix-vite-plus";
    llm-agents.url = "github:numtide/llm-agents.nix";
  };

  outputs = inputs@{ nixpkgs, home-manager, moonbit-overlay, codex-desktop-linux, nix-vite-plus, llm-agents, ... }:
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
            ({ pkgs, ... }:
            let
              codexDmgUrl = "https://persistent.oaistatic.com/codex-app-prod/ChatGPT.dmg";
              upstreamCodexDmg = pkgs.fetchurl {
                url = codexDmgUrl;
                hash = "sha256-QONIFOdOMJQ8IJ69TalM1N41gaUsW/++K88uSI1jYcY=";
              };
              currentCodexDmg = pkgs.fetchurl {
                url = codexDmgUrl;
                hash = "sha256-Wiq5aJ9Lo4/LE1VlJG1covEk1Tkzagoyr823IEDSFGY=";
              };
              upstreamCodexPackages = codex-desktop-linux.packages.${system};
              patchedCodexDesktop = upstreamCodexPackages.codex-desktop.overrideAttrs (old: {
                src =
                  let
                    payload = old.src;
                  in
                  pkgs.stdenv.mkDerivation {
                    inherit (payload) pname version src nativeBuildInputs;
                    dontConfigure = true;
                    dontBuild = true;
                    installPhase =
                      let
                        upstreamDmgPath = builtins.unsafeDiscardStringContext "${upstreamCodexDmg}";
                        currentDmgPath = builtins.unsafeDiscardStringContext "${currentCodexDmg}";
                        payloadContextKeys = builtins.attrNames (builtins.getContext payload.installPhase);
                        upstreamDmgContextKeys = builtins.filter
                          (key: builtins.match ".*-ChatGPT\\.dmg\\.drv" key != null)
                          payloadContextKeys;
                        payloadContext = builtins.removeAttrs
                          (builtins.getContext payload.installPhase)
                          upstreamDmgContextKeys;
                        patchedInstallPhase = builtins.replaceStrings
                          [ upstreamDmgPath ]
                          [ currentDmgPath ]
                          (builtins.unsafeDiscardStringContext payload.installPhase);
                      in
                      builtins.appendContext patchedInstallPhase
                        (payloadContext // builtins.getContext "${currentCodexDmg}");
                  };
              });
              patchedCodexDesktopInput = codex-desktop-linux // {
                packages = codex-desktop-linux.packages // {
                  "${system}" = upstreamCodexPackages // {
                    codex-desktop = patchedCodexDesktop;
                  };
                };
              };
            in
            {
              nixpkgs.overlays = [
                moonbit-overlay.overlays.default
                nix-vite-plus.overlays.default
                llm-agents.overlays.default
              ];
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = {
                codex-desktop-linux = patchedCodexDesktopInput;
                inherit system;
              };
              home-manager.users.${username} = import ./users/nakasyou/home.nix;
            })
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
