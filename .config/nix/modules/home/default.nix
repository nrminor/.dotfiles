# Home-manager configuration entry point
#
# This module defines user-level configuration that works across
# platforms (macOS, NixOS, standalone Linux). It imports sub-modules
# and sets core home-manager options.
#
# Note: Dotfiles are managed by dotter, not home-manager.
# We only use home-manager for packages and program integrations
# that benefit from its module system (like direnv).
{
  pkgs,
  lib,
  inputs,
  username,
  ...
}:

let
  # Determine home directory based on platform
  homeDir = if pkgs.stdenv.isDarwin then "/Users/${username}" else "/home/${username}";
in
{
  imports = [
    ./packages.nix
    ./programs.nix
  ];

  # Required: username and home directory
  home.username = username;
  home.homeDirectory = lib.mkForce homeDir;

  # Required: tells home-manager which version's defaults to use
  # Set this once and don't change it unless you read the release notes
  home.stateVersion = "24.05";

  # Let home-manager manage itself when running standalone
  # (This is a no-op when integrated with darwin/nixos)
  programs.home-manager.enable = true;
}
