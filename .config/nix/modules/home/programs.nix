# Home-manager program configurations
#
# Program-specific settings that benefit from home-manager's
# module system. We keep this minimal since dotter manages
# most dotfiles.
{ pkgs, inputs, ... }:

let
  pkgs-stable = inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  nuPluginPolarsEthnumPatch = ./nu-plugin-polars-ethnum-1.5.3.patch;
  nuPluginPolars = pkgs.nushellPlugins.polars.overrideAttrs (
    oldAttrs:
    let
      cargoPatches = (oldAttrs.cargoPatches or [ ]) ++ [ nuPluginPolarsEthnumPatch ];
      cargoHash = "sha256-Cpv58bqpx1o0Dz2AykqzFY+PQE/Updr5MusQflpEF74=";
    in
    {
      # overrideAttrs runs after buildRustPackage derives `patches` and
      # `cargoDeps`, so update both the source and vendored dependencies.
      inherit cargoHash cargoPatches;
      patches = (oldAttrs.patches or [ ]) ++ [ nuPluginPolarsEthnumPatch ];
      cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
        inherit (oldAttrs) pname version src;
        hash = cargoHash;
        patches = cargoPatches;
      };
    }
  );
in
{
  # Generate the plugin registry with the same Nushell package that will load it.
  # This keeps plugin protocol versions and Nix store paths in sync across upgrades.
  programs.nushell = {
    enable = true;
    package = pkgs.nushell;
    configDir = ".config/nushell";
    plugins = [
      nuPluginPolars
      pkgs.nushellPlugins.query
      pkgs.nushellPlugins.gstat
      pkgs.nushellPlugins.formats
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
