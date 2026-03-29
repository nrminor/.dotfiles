# Neovim configuration via nixvim
#
# Based on IMax153's nixvim config (https://github.com/IMax153/nixvim),
# integrated as a home-manager module. The actual config lives in
# ./nixvim/config/ and is imported as nixvim modules.
{ inputs, pkgs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  fffPlugin = inputs.fff-nvim.packages.${system}.fff-nvim;
  rustowlPlugin = inputs.rustowl-flake.packages.${system}.rustowl-nvim;
  rustowl = inputs.rustowl-flake.packages.${system}.rustowl;
in
{
  imports = [
    inputs.nixvim.homeModules.nixvim
  ];

  programs.nixvim = {
    enable = true;
    imports = [ ../../../neovim ];
    _module.args = {
      inherit fffPlugin rustowlPlugin rustowl;
    };
  };
}
