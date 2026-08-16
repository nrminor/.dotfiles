# Neovim configuration via nixvim
#
# Based on IMax153's nixvim config (https://github.com/IMax153/nixvim),
# integrated as a home-manager module. The actual config lives in
# ./nixvim/config/ and is imported as nixvim modules.
{ inputs, pkgs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  pkgs-stable = inputs.nixpkgs-stable.legacyPackages.${system};
  fffPlugin = inputs.fff-nvim.packages.${system}.fff-nvim;
  oyuiPackage = inputs.oyui.packages.${system}.default;
  optionalNeovimFeatures = {
    gleam = false;
  };
in
{
  imports = [
    inputs.nixvim.homeModules.nixvim
  ];

  programs.nixvim = {
    enable = true;
    nixpkgs.source = inputs.nixpkgs;
    imports = [ ../../../nixvim ];
    _module.args = {
      inherit
        fffPlugin
        oyuiPackage
        optionalNeovimFeatures
        pkgs-stable
        ;
    };
  };
}
