{
  description = "NRM cross-platform Nix configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";

    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    homebrew-steipete = {
      url = "github:steipete/homebrew-tap";
      flake = false;
    };

    jj-starship.url = "github:dmmulroy/jj-starship";
  };

  outputs =
    inputs@{
      self,
      nix-darwin,
      nixpkgs,
      nix-homebrew,
      ...
    }:
    let
      # Helper function to create a darwin system configuration
      mkDarwin =
        {
          hostname,
          system ? "aarch64-darwin",
          username ? "nickminor",
        }:
        nix-darwin.lib.darwinSystem {
          inherit system;

          # specialArgs makes these values available to ALL modules
          specialArgs = {
            inherit inputs username;
          };

          modules = [
            # Third-party module for Homebrew management
            nix-homebrew.darwinModules.nix-homebrew

            # Our darwin configuration (imports common data internally)
            ./modules/darwin
          ];
        };
    in
    {
      # macOS configurations
      darwinConfigurations = {
        "starter" = mkDarwin { hostname = "starter"; };
      };

      # Expose the package set for convenience
      darwinPackages = self.darwinConfigurations."starter".pkgs;
    };
}
