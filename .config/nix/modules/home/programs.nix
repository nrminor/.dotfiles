# Home-manager program configurations
#
# Program-specific settings that benefit from Home Manager's module system.
# User-level dotfile deployment remains mise's responsibility.
{ pkgs, inputs, ... }:

let
  pkgs-stable = inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  # Direnv loads project-specific environments; nix-direnv caches `use flake`.
  programs.direnv = {
    enable = true;
    package = pkgs-stable.direnv;
    nix-direnv.enable = true;
    enableNushellIntegration = false; # Nushell config already defines the hook
  };
}
