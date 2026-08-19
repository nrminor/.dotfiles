{
  description = "NRM macOS nix-darwin configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      self,
      nix-darwin,
      ...
    }:
    let
      # Helper function to create a darwin system configuration
      mkDarwin =
        {
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
            ./modules/darwin
          ];
        };
    in
    {
      # macOS configurations
      darwinConfigurations = {
        "starter" = mkDarwin { };
      };
    };
}
