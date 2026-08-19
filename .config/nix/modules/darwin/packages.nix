# Darwin packages
#
# Packages belonging to the optional macOS system layer.
{ pkgs, ... }:

{
  environment.pathsToLink = [ "/share/nix-direnv" ];

  environment.systemPackages = [
    # Scoped Nix project environments
    pkgs.direnv
    pkgs.nix-direnv

    # Maintenance tools for this Nix configuration
    pkgs.nixd
    pkgs.nixfmt
    pkgs.nil
    pkgs.statix
  ];
}
