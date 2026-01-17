# Darwin packages
#
# Packages that only make sense on macOS. The bulk of packages
# are now managed by home-manager (modules/home/packages.nix).
{ pkgs, ... }:

{
  environment.systemPackages = [
    pkgs.mkalias # Creates macOS aliases for Spotlight
    pkgs.skhd # macOS hotkey daemon
  ];
}
