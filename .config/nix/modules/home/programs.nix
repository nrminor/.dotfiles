# Home-manager program configurations
#
# Program-specific settings that benefit from Home Manager's module system.
# User-level dotfile deployment remains mise's responsibility.
{ pkgs, inputs, ... }:

let
  pkgs-stable = inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  # Generate the plugin registry with the same Nushell package that will load it.
  # This keeps plugin protocol versions and Nix store paths in sync across upgrades.
  programs.nushell = {
    enable = true;
    package = pkgs.nushell;
    configDir = ".config/nushell";
    plugins = [
      pkgs.nushellPlugins.polars
      pkgs.nushellPlugins.query
      pkgs.nushellPlugins.gstat
      pkgs.nushellPlugins.formats
    ];
  };
  # The registry is generated state; replace stale mutable copies on activation.
  home.file.".config/nushell/plugin.msgpackz".force = true;

  # Direnv loads project-specific environments; nix-direnv caches `use flake`.
  programs.direnv = {
    enable = true;
    package = pkgs-stable.direnv;
    nix-direnv.enable = true;
    enableNushellIntegration = false; # Nushell config already defines the hook
  };
}
