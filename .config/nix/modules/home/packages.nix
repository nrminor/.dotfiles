# Home-manager packages
#
# Imports the common package list and assigns it to home.packages.
# These packages are installed in the user's profile, not system-wide.
{ pkgs, inputs, ... }:

let
  commonPackages = import ../common/packages.nix { inherit pkgs inputs; };
in
{
  home.packages = commonPackages;
}
