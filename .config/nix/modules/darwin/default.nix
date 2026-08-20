# Darwin-specific configuration entry point
#
# This module imports all darwin-specific sub-modules and sets
# core nix-darwin options that don't fit elsewhere.
{
  config,
  pkgs,
  lib,
  inputs,
  username,
  ...
}:

{
  imports = [
    ./packages.nix
    ./system.nix
    ./shell.nix
    ./environment.nix
    ./activation.nix
  ];

  # The primary user for this system
  system.primaryUser = username;

  # Track which git commit this config came from
  system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;

  # State version for darwin (read changelog before changing)
  system.stateVersion = 5;

  # Platform architecture
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-darwin";

  # Allow closed-source packages
  nixpkgs.config.allowUnfree = true;

  # Avoid building nix-darwin's generated HTML manual. This has broken before
  # when nixpkgs' nixos-render-docs CLI changed ahead of nix-darwin.
  documentation.doc.enable = false;

  # The generated uninstaller evaluates a separate uninstall system that can
  # still pull in nix-darwin's HTML manual even when docs are disabled here.
  system.tools.darwin-uninstaller.enable = false;

  # Nix daemon configuration
  nix = {
    settings.experimental-features = "nix-command flakes";

    # Automatic garbage collection
    gc = {
      automatic = true;
      interval = {
        Day = 7;
      };
      options = "--delete-older-than 30d";
    };
  };
}
