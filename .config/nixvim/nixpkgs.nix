# nixpkgs overlay (no-op)
#
# The original config created a pkgs.unstable overlay, but in our
# home-manager setup pkgs already comes from nixpkgs-unstable.
# References to pkgs.unstable.* have been replaced with pkgs.* directly.
{ ... }:
{
}
