{
  description = "NRM macOS nix-darwin configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";

    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      self,
      nix-darwin,
      nixpkgs,
      home-manager,
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
            # Home-manager integration (user-level packages and config)
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.${username} = import ./modules/home;
              home-manager.extraSpecialArgs = { inherit inputs username; };
            }

            # Our darwin configuration
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
