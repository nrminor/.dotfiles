# Home-manager program configurations
#
# Program-specific settings that benefit from home-manager's
# module system. We keep this minimal since dotter manages
# most dotfiles.
{ pkgs, inputs, ... }:

let
  pkgs-stable = inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  # Direnv: automatically load/unload environment variables per directory
  # home-manager handles shell integration for bash/zsh/fish/nushell
  programs.direnv = {
    enable = true;
    package = pkgs-stable.direnv;
    nix-direnv.enable = true; # Makes 'use flake' fast by caching
  };
}
