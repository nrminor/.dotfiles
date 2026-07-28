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
  # Generate the plugin registry with the same Nushell package that will load it.
  # This keeps plugin protocol versions and Nix store paths in sync across upgrades.
  programs.nushell = {
    enable = true;
    package = pkgs.nushell;
    configDir = ".config/nushell";
    plugins = with pkgs.nushellPlugins; [
      polars
      query
      gstat
      formats
    ];
  };
  # The registry is generated state; replace stale mutable copies on activation.
  home.file.".config/nushell/plugin.msgpackz".force = true;

  # Direnv: automatically load/unload environment variables per directory
  # home-manager handles shell integration for bash/zsh/fish/nushell
  programs.direnv = {
    enable = true;
    package = pkgs-stable.direnv;
    nix-direnv.enable = true; # Makes 'use flake' fast by caching
    enableNushellIntegration = false; # Nushell config already defines the hook
  };
}
