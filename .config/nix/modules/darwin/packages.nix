# Darwin packages
#
# Imports the common package list and adds darwin-specific packages,
# then assigns them to environment.systemPackages.
{ pkgs, inputs, ... }:

let
  commonPackages = import ../common/packages.nix { inherit pkgs inputs; };

  # Packages that only make sense on macOS
  darwinPackages = [
    pkgs.mkalias # Creates macOS aliases for Spotlight
    pkgs.skhd # macOS hotkey daemon
  ];
in
{
  environment.systemPackages = commonPackages ++ darwinPackages;
}
