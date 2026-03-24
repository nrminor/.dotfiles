# Neovim configuration via nixvim
#
# Based on IMax153's nixvim config (https://github.com/IMax153/nixvim),
# integrated as a home-manager module. The actual config lives in
# ./nixvim/config/ and is imported as nixvim modules.
{ inputs, pkgs, ... }:

let
  fffPlugin = inputs.fff-nvim.packages.${pkgs.stdenv.hostPlatform.system}.fff-nvim;
in
{
  imports = [
    inputs.nixvim.homeModules.nixvim
  ];

  programs.nixvim = {
    enable = true;
    imports = [ ../../../neovim ];
    _module.args.fffPlugin = fffPlugin;
  };
}
